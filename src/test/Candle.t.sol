pragma solidity ^0.8.6;

import "ds-test/test.sol";

import "./Hevm.sol";
import "../Candle.sol";
import "../TestNFT.sol";

contract Bidder {
    Candle candle;
    uint256 auctionId;

    receive() external payable{}

    constructor(Candle _candle, uint256 _auctionId) payable {
        auctionId = _auctionId;
        candle = _candle;
    }

    function increaseAuctionBid(uint256 bidAmount) public {
        candle.addToBid{value: bidAmount}(auctionId);
    }

    function withdrawBid() public {
        candle.withdraw(auctionId);
    }

    function balance() public returns (uint256) {
        return address(this).balance;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

contract CandleTest is DSTest {
    Hevm internal constant hevm = Hevm(HEVM_ADDRESS);

    Candle candle;
    TestNFT nft;
    Bidder Alice;
    Bidder Bob;
    uint256 longAuction;

    struct Auction {
        address tokenAddress;
        uint256 tokenId;
        address seller;
        uint256 closingBlock;
        uint256 finalBlock;
        address currentHighestBidder;
        mapping(uint256 => address) highestBidderAtIndex;
        mapping(address => uint256) cumululativeBidFromBidder;
    }

    event Print(string msg, uint256 value);
    receive() external payable {}

    function setUp() public {
        candle = new Candle();
        nft = new TestNFT();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }

    function test_create_nft() public {
        nft.mint(address(this), "");
    }

    function test_create_auction() public {
        uint256 tokenId = nft.mint(address(this), "");
        nft.approve(address(candle), tokenId);
        candle.createAuction(
            address(nft),
            tokenId,
            150,
            50,
	    0
        );
    }

    function test_create_and_bid() public {
        uint256 tokenId = nft.mint(address(this), "");
        nft.approve(address(candle), tokenId);
        uint256 aid = candle.createAuction(
            address(nft),
            tokenId,
            150,
            50,
	    0
        );
        Alice = new Bidder{value: 10 ether}(candle, aid);
        Bob = new Bidder{value: 10 ether}(candle, aid);
        address highest;
        uint256 amount;

        Alice.increaseAuctionBid(1 ether);
        (highest, amount) = candle.getHighestBid(aid);
        assertEq(highest, address(Alice));
        assertEq(amount, 1 ether);

        hevm.roll(block.number + 1);

        Bob.increaseAuctionBid(1.2 ether);
        (highest, amount) = candle.getHighestBid(aid);
        assertEq(highest, address(Bob));
        assertEq(amount, 1.2 ether);

        hevm.roll(block.number + 1);

        Alice.increaseAuctionBid(1 ether);
        (highest, amount) = candle.getHighestBid(aid);
        assertEq(highest, address(Alice));
        assertEq(amount, 2 ether);
    }

    function testFail_bid_after_finalised() public {
        uint256 tokenId = nft.mint(address(this), "");
        nft.approve(address(candle), tokenId);
        uint256 aid = candle.createAuction(
            address(nft),
            tokenId,
            150,
            50,
	    0
        );
        Alice = new Bidder{value: 10 ether}(candle, aid);
        Bob = new Bidder{value: 10 ether}(candle, aid);
        Alice.increaseAuctionBid(1 ether);
        hevm.roll(block.number + 200);
        // should fail as past last block
        Bob.increaseAuctionBid(2 ether);
    }

    function testFail_finalise_early() public {
        uint256 tokenId = nft.mint(address(this), "");
        nft.approve(address(candle), tokenId);
        uint256 aid = candle.createAuction(
            address(nft),
            tokenId,
            150,
            50,
	    0
        );
        hevm.roll(block.number + 150);
        candle.manualFulfil(aid, uint256(blockhash(block.number - 1)));
    }

    function test_finalise_auction() public {
        uint256 tokenId = nft.mint(address(this), "");
        nft.approve(address(candle), tokenId);
        uint256 aid = candle.createAuction(
            address(nft),
            tokenId,
            150,
            50,
	    0
        );
        Alice = new Bidder{value: 10 ether}(candle, aid);
        Bob = new Bidder{value: 10 ether}(candle, aid);
        Alice.increaseAuctionBid(1 ether);
        hevm.roll(block.number + 1);
        Bob.increaseAuctionBid(2 ether);
        hevm.roll(block.number + 152);
        candle.manualFulfil(aid, uint256(blockhash(block.number - 1)));
    }

    // Testing NFT correctly returned if there are no bids at all.
    function test_no_bids_withdraw() public {
        uint256 tokenId = nft.mint(address(this), "");
        assertEq(nft.balanceOf(address(this)), 1);
        nft.approve(address(candle), tokenId);
        uint256 aid = candle.createAuction(
            address(nft),
            tokenId,
            150,
            50,
	    0
        );
        assertEq(nft.balanceOf(address(this)), 0);
        hevm.roll(block.number + 152);
        candle.manualFulfil(aid, uint256(blockhash(block.number - 1)));
        candle.withdraw(aid);
        assertEq(nft.balanceOf(address(this)), 1);
    }

    // Testing NFT correctly returned if there are was one bid.
    // Bidder should be able to withdraw NFT.
    // Seller should be able to withdraw deposited tokens.
    function test_one_bid_withdraw() public {
        uint256 tokenId = nft.mint(address(this), "");
        assertEq(nft.balanceOf(address(this)), 1);
        nft.approve(address(candle), tokenId);
        uint256 aid = candle.createAuction(
            address(nft),
            tokenId,
            150,
            50,
	    0
        );
        assertEq(nft.balanceOf(address(this)), 0);
        Alice = new Bidder{value: 10 ether}(candle, aid);
        assertEq(Alice.balance(), 10 ether);
        Alice.increaseAuctionBid(1 ether);
        assertEq(Alice.balance(), 9 ether);
        hevm.roll(block.number + 152);
        candle.manualFulfil(aid, uint256(blockhash(block.number - 1)));

	uint preBalance = address(this).balance;
        candle.withdraw(aid);
        assertEq(nft.balanceOf(address(this)), 0);
        assertEq(address(this).balance - preBalance, 1 ether);
        Alice.withdrawBid();
        assertEq(nft.balanceOf(address(Alice)), 1);
    }

    function testFail_withdraw_early() public {
        uint256 tokenId = nft.mint(address(this), "");
        assertEq(nft.balanceOf(address(this)), 1);
        nft.approve(address(candle), tokenId);
        uint256 aid = candle.createAuction(
            address(nft),
            tokenId,
            150,
            50,
	    0
        );
        assertEq(nft.balanceOf(address(this)), 0);
        Alice = new Bidder{value: 10 ether}(candle, aid);
        Alice.increaseAuctionBid(1 ether);
        hevm.roll(block.number + 1);
        Alice.withdrawBid();
    }

    // Testing 2 bid NFT withdraw
    // Bob wins the auction and should be able to withdraw a NFT
    // Alice loses the auction and can withdraw her bid
    // NFT Owner withdraws Bobs bid.
    function test_two_bid_withdraw() public {
        uint256 tokenId = nft.mint(address(this), "");
        assertEq(nft.balanceOf(address(this)), 1);
        nft.approve(address(candle), tokenId);
        uint256 aid = candle.createAuction(
            address(nft),
            tokenId,
            150,
            50,
	    0
        );
        assertEq(nft.balanceOf(address(this)), 0);
        Alice = new Bidder{value: 10 ether}(candle, aid);
        Bob = new Bidder{value: 10 ether}(candle, aid);
        assertEq(Alice.balance(), 10 ether);
        assertEq(Bob.balance(), 10 ether);
        Alice.increaseAuctionBid(1 ether);
        hevm.roll(block.number + 1);
        Bob.increaseAuctionBid(2 ether);
        assertEq(Alice.balance(), 9 ether);
        assertEq(Bob.balance(), 8 ether);
        hevm.roll(block.number + 152);
        candle.manualFulfil(aid, uint256(blockhash(block.number - 1)));

	uint preBalance = address(this).balance;
        candle.withdraw(aid);
        assertEq(nft.balanceOf(address(this)), 0);
        assertEq(address(this).balance - preBalance, 2 ether);
        Alice.withdrawBid();
        assertEq(Alice.balance(), 10 ether);
        assertEq(nft.balanceOf(address(Alice)), 0);

        Bob.withdrawBid();
        assertEq(Bob.balance(), 8 ether);
        assertEq(nft.balanceOf(address(Bob)), 1);
    }

    // Alice bets on closingBlock
    // Bob bets on closingBlock + 1
    // Auction finalised on closingBlock
    function test_closing_window() public {
        uint256 tokenId = nft.mint(address(this), "");
        nft.approve(address(candle), tokenId);
        uint256 aid = candle.createAuction(
            address(nft),
            tokenId,
            150,
            50,
	    0
        );
        Alice = new Bidder{value: 10 ether}(candle, aid);
        Bob = new Bidder{value: 10 ether}(candle, aid);
        // Put us in the first block of the bidding window.
        hevm.roll(block.number + 100);
        Alice.increaseAuctionBid(1 ether);
        hevm.roll(block.number + 1);
        Bob.increaseAuctionBid(2 ether);
        hevm.roll(block.number + 60);
        // Finalise on the first closingBlock (randomness=0)
        candle.manualFulfil(aid, 0);
        (address highest, uint256 amount) = candle.getHighestBid(aid);
        assertEq(highest, address(Alice));
        assertEq(amount, 1 ether);

        Alice.withdrawBid();
        assertEq(nft.balanceOf(address(Alice)), 1);
        assertEq(Alice.balance(), 9 ether);
        Bob.withdrawBid();
        assertEq(nft.balanceOf(address(Bob)), 0);
        assertEq(Bob.balance(), 10 ether);
    }

    // Alice bets on finalBlock-1 - 1
    // Bob bets on finalBlock - 2eth
    // Auction finalised on finalBlock
    function test_final_block() public {
        uint256 tokenId = nft.mint(address(this), "");
        nft.approve(address(candle), tokenId);
        uint256 aid = candle.createAuction(
            address(nft),
            tokenId,
            150,
            50,
	    0
        );
        Alice = new Bidder{value: 10 ether}(candle, aid);
        Bob = new Bidder{value: 10 ether}(candle, aid);
        // Put us in the first block of the bidding window.
        hevm.roll(block.number + 149);
        Alice.increaseAuctionBid(1 ether);
        hevm.roll(block.number + 1);
        Bob.increaseAuctionBid(2 ether);
        hevm.roll(block.number + 10);
        // Finalise on the first closingBlock (randomness=0)
        candle.manualFulfil(aid, 50);
        (address highest, uint256 amount) = candle.getHighestBid(aid);
        assertEq(highest, address(Bob));
        assertEq(amount, 2 ether);

	uint preBalance = address(this).balance;
        candle.withdraw(aid);
        assertEq(nft.balanceOf(address(this)), 0);
        assertEq(address(this).balance - preBalance, 2 ether);

        Alice.withdrawBid();
        assertEq(nft.balanceOf(address(Alice)), 0);
        assertEq(Alice.balance(), 10 ether);
        Bob.withdrawBid();
        assertEq(nft.balanceOf(address(Bob)), 1);
        assertEq(Bob.balance(), 8 ether);
    }

    // Alice bids on closingBlock + 3
    // Bob bids on closingBlock + 10
    // Auction finalises on closingBlock + 5, Alice wins.
    function test_finalise_halfway() public {
        uint256 tokenId = nft.mint(address(this), "");
        nft.approve(address(candle), tokenId);
        uint256 startBlock = block.number;
        uint256 aid = candle.createAuction(
            address(nft),
            tokenId,
            150,
            50,
	    0
        );
        Alice = new Bidder{value: 10 ether}(candle, aid);
        Bob = new Bidder{value: 10 ether}(candle, aid);
        // Put us in the first block of the bidding window.
        hevm.roll(startBlock + 103);
        Alice.increaseAuctionBid(1 ether);
        hevm.roll(startBlock + 110);
        Bob.increaseAuctionBid(2 ether);
        hevm.roll(startBlock + 160);
        // Finalise on the first closingBlock (randomness=0)
        candle.manualFulfil(aid, 5);
        (address highest, uint256 amount) = candle.getHighestBid(aid);
        assertEq(highest, address(Alice));
        assertEq(amount, 1 ether);

	uint preBalance = address(this).balance;
        candle.withdraw(aid);
        assertEq(nft.balanceOf(address(this)), 0);
        assertEq(address(this).balance - preBalance, 1 ether);

        Alice.withdrawBid();
        assertEq(nft.balanceOf(address(Alice)), 1);
        assertEq(Alice.balance(), 9 ether);
        Bob.withdrawBid();
        assertEq(nft.balanceOf(address(Bob)), 0);
        assertEq(Bob.balance(), 10 ether);
    }

    // Alice bids on closingBlock + 3
    // Bob bids on closingBlock + 10
    // Auction finalises on closingBlock + 11, Bob wins.
    function test_finalise_halfway2() public {
        uint256 tokenId = nft.mint(address(this), "");
        nft.approve(address(candle), tokenId);
        uint256 startBlock = block.number;
        uint256 aid = candle.createAuction(
            address(nft),
            tokenId,
            150,
            50,
	    0
        );
        Alice = new Bidder{value: 10 ether}(candle, aid);
        Bob = new Bidder{value: 10 ether}(candle, aid);
        // Put us in the first block of the bidding window.
        hevm.roll(startBlock + 103);
        Alice.increaseAuctionBid(1 ether);
        hevm.roll(startBlock + 110);
        Bob.increaseAuctionBid(2 ether);
        hevm.roll(startBlock + 160);
        // Finalise on the first closingBlock (randomness=0)
        candle.manualFulfil(aid, 11);
        (address highest, uint256 amount) = candle.getHighestBid(aid);
        assertEq(highest, address(Bob));
        assertEq(amount, 2 ether);

	uint preBalance = address(this).balance;
        candle.withdraw(aid);
        assertEq(nft.balanceOf(address(this)), 0);
        assertEq(address(this).balance - preBalance, 2 ether);

        Alice.withdrawBid();
        assertEq(nft.balanceOf(address(Alice)), 0);
        assertEq(Alice.balance(), 10 ether);
        Bob.withdrawBid();
        assertEq(nft.balanceOf(address(Bob)), 1);
        assertEq(Bob.balance(), 8 ether);
    }

    function test_checkUpkeep() public {
        uint256 tokenId = nft.mint(address(this), "");
        nft.approve(address(candle), tokenId);
        uint256 startBlock = block.number;
        uint256 aid = candle.createAuction(
            address(nft),
            tokenId,
            150,
            50,
	    0
        );
        hevm.roll(startBlock + 160);
	(bool upkeepNeeded, bytes memory performData) = candle.checkUpkeep(bytes(""));
        (uint256 blockNum, uint256[] memory requestIdsToFinalise) = abi.decode(performData, (uint, uint256[]));
	assertTrue(upkeepNeeded);
	assertEq(requestIdsToFinalise[0], aid);
	assertEq(blockNum, startBlock+151);
    }

    function testFail_multiple_withdraw() public {
        uint256 tokenId = nft.mint(address(this), "");
        nft.approve(address(candle), tokenId);
        uint256 startBlock = block.number;
        uint256 aid = candle.createAuction(
            address(nft),
            tokenId,
            150,
            50,
	    0
        );

        Alice = new Bidder{value: 10 ether}(candle, aid);
        Alice.increaseAuctionBid(1 ether);
        hevm.roll(startBlock + 160);
	// Finish the auction
        candle.manualFulfil(aid, 1);
        (address highest, uint256 amount) = candle.getHighestBid(aid);
        assertEq(highest, address(Alice));
        assertEq(amount, 1 ether);

        Alice.withdrawBid();
        assertEq(nft.balanceOf(address(Alice)), 1);
        assertEq(Alice.balance(), 9 ether);
	// Try and withdraw twice
        Alice.withdrawBid();
    }

    function testFail_no_cancel() public {
        uint256 tokenId = nft.mint(address(this), "");
        nft.approve(address(candle), tokenId);
        uint256 aid = candle.createAuction(
            address(nft),
            tokenId,
            150,
            50,
	    2 ether
        );
        Alice = new Bidder{value: 10 ether}(candle, aid);
        Alice.increaseAuctionBid(3 ether);
	// Should fail as highest bid is above minbid
	candle.cancelAuction(aid);
    }

    function test_can_cancel() public {
        uint256 tokenId = nft.mint(address(this), "");
        nft.approve(address(candle), tokenId);
        uint256 aid = candle.createAuction(
            address(nft),
            tokenId,
            150,
            50,
	    2 ether
        );
        Alice = new Bidder{value: 10 ether}(candle, aid);
        Alice.increaseAuctionBid(1 ether);
	// Should fail as highest bid is above minbid
	candle.cancelAuction(aid);
	Alice.withdrawBid();
        assertEq(nft.balanceOf(address(Alice)), 0);
        assertEq(Alice.balance(), 10 ether);
    }

    function test_not_above_min() public {
        uint256 tokenId = nft.mint(address(this), "");
        nft.approve(address(candle), tokenId);
        uint256 aid = candle.createAuction(
            address(nft),
            tokenId,
            150,
            50,
	    2 ether
        );
        Alice = new Bidder{value: 10 ether}(candle, aid);
        Alice.increaseAuctionBid(1 ether);
	hevm.roll(block.number + 160);
        candle.manualFulfil(aid, 2);
	Alice.withdrawBid();
	assertEq(nft.balanceOf(address(Alice)), 0);
        assertEq(Alice.balance(), 10 ether);
    }


    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
