pragma solidity ^0.8.6;

import "ds-test/test.sol";

import "./Hevm.sol";
import "../Candle.sol";
import "../TestNFT.sol";

interface WETH {
    function balanceOf(address) external returns (uint);
    function deposit() external payable;
    function approve(address,uint) external;
}

contract NFTSeller{
}
contract Bidder {
	Candle candle;
	uint auctionId;
	WETH weth;

	constructor(Candle _candle, uint _auctionId) payable {
		auctionId = _auctionId;
		candle = _candle;
		weth = WETH(0xd0A1E359811322d97991E03f863a0C30C2cF029C);
		weth.deposit{value: 10 ether}();
		weth.approve(address(candle), 2**256 - 1);
	}
	function increaseAuctionBid(uint bidAmount) public {
		candle.addToBid(auctionId, bidAmount);
	}

	function withdrawBid() public {
		candle.withdraw(auctionId);
	}

	function balance() public returns (uint) {
		return weth.balanceOf(address(this));
	}
	function onERC721Received(address, address, uint256, bytes memory) public returns(bytes4) {
		return this.onERC721Received.selector;
	}
}

contract CandleTest is DSTest {
    Hevm internal constant hevm = Hevm(HEVM_ADDRESS);

    Candle candle;
    TestNFT nft;
    WETH weth;
    Bidder Alice;
    Bidder Bob;
    //NFTSeller Candice;

    struct Auction {
        address tokenAddress;
        uint tokenId;
        address seller;
        uint closingBlock;
        uint finalBlock;
        address bidToken;
        address currentHighestBidder;
        mapping (uint => address) highestBidderAtIndex;
        mapping (address => uint) cumululativeBidFromBidder;
    }

    event Print(string msg, uint value);
    
    function setUp() public {
        candle = new Candle();
        nft = new TestNFT();
        weth = WETH(0xd0A1E359811322d97991E03f863a0C30C2cF029C);
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }

    function test_create_nft() public {
        nft.mint(address(this));
    }

    function test_create_auction() public {
        uint tokenId = nft.mint(address(this));
        nft.approve(address(candle), tokenId);
        candle.createAuction(address(nft), tokenId, block.number + 100, block.number + 150, address(weth));
    }

    function test_create_and_bid() public {
        uint tokenId = nft.mint(address(this));
        nft.approve(address(candle), tokenId);
        uint aid = candle.createAuction(address(nft), tokenId, block.number + 100, block.number + 150, address(weth));
	Alice = new Bidder{value: 10 ether}(candle, aid);
	Bob = new Bidder{value: 10 ether}(candle, aid);
	address highest;
	uint amount;

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
        uint tokenId = nft.mint(address(this));
        nft.approve(address(candle), tokenId);
        uint aid = candle.createAuction(address(nft), tokenId, block.number + 100, block.number + 150, address(weth));
	Alice = new Bidder{value: 10 ether}(candle, aid);
	Bob = new Bidder{value: 10 ether}(candle, aid);
	Alice.increaseAuctionBid(1 ether);
	hevm.roll(block.number + 200);
	// should fail as past last block
	Bob.increaseAuctionBid(2 ether);
    }
    function testFail_finalise_early() public {
        uint tokenId = nft.mint(address(this));
        nft.approve(address(candle), tokenId);
        uint aid = candle.createAuction(address(nft), tokenId, block.number + 100, block.number + 150, address(weth));
	hevm.roll(block.number + 105);
	candle.manualFulfil(aid, uint(blockhash(block.number - 1)));
    }

    function test_finalise_auction() public {
        uint tokenId = nft.mint(address(this));
        nft.approve(address(candle), tokenId);
        uint aid = candle.createAuction(address(nft), tokenId, block.number + 100, block.number + 150, address(weth));
	Alice = new Bidder{value: 10 ether}(candle, aid);
	Bob = new Bidder{value: 10 ether}(candle, aid);
	Alice.increaseAuctionBid(1 ether);
	hevm.roll(block.number + 1);
	Bob.increaseAuctionBid(2 ether);
	hevm.roll(block.number + 152);
	candle.manualFulfil(aid, uint(blockhash(block.number - 1)));
    }

    // Testing NFT correctly returned if there are no bids at all.
    function test_no_bids_withdraw() public {
        uint tokenId = nft.mint(address(this));
	assertEq(nft.balanceOf(address(this)), 1);
        nft.approve(address(candle), tokenId);
        uint aid = candle.createAuction(address(nft), tokenId, block.number + 100, block.number + 150, address(weth));
	assertEq(nft.balanceOf(address(this)), 0);
	hevm.roll(block.number + 152);
	candle.manualFulfil(aid, uint(blockhash(block.number - 1)));
	candle.withdraw(aid);
	assertEq(nft.balanceOf(address(this)), 1);
    }

    // Testing NFT correctly returned if there are was one bid.
    // Bidder should be able to withdraw NFT.
    // Seller should be able to withdraw deposited tokens.
    function test_one_bid_withdraw() public {
        uint tokenId = nft.mint(address(this));
	assertEq(nft.balanceOf(address(this)), 1);
        nft.approve(address(candle), tokenId);
        uint aid = candle.createAuction(address(nft), tokenId, block.number + 100, block.number + 150, address(weth));
	assertEq(nft.balanceOf(address(this)), 0);
	Alice = new Bidder{value: 10 ether}(candle, aid);
	assertEq(Alice.balance(), 10 ether);
	Alice.increaseAuctionBid(1 ether);
	assertEq(Alice.balance(), 9 ether);
	hevm.roll(block.number + 152);
	candle.manualFulfil(aid, uint(blockhash(block.number - 1)));
	candle.withdraw(aid);
	assertEq(nft.balanceOf(address(this)), 0);
	assertEq(weth.balanceOf(address(this)), 1 ether);
	Alice.withdrawBid();
	assertEq(nft.balanceOf(address(Alice)), 1);
    }

    function testFail_withdraw_early() public {
        uint tokenId = nft.mint(address(this));
	assertEq(nft.balanceOf(address(this)), 1);
        nft.approve(address(candle), tokenId);
        uint aid = candle.createAuction(address(nft), tokenId, block.number + 100, block.number + 150, address(weth));
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
        uint tokenId = nft.mint(address(this));
	assertEq(nft.balanceOf(address(this)), 1);
        nft.approve(address(candle), tokenId);
        uint aid = candle.createAuction(address(nft), tokenId, block.number + 100, block.number + 150, address(weth));
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
	candle.manualFulfil(aid, uint(blockhash(block.number - 1)));
	candle.withdraw(aid);
	assertEq(nft.balanceOf(address(this)), 0);
	assertEq(weth.balanceOf(address(this)), 2 ether);
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
        uint tokenId = nft.mint(address(this));
        nft.approve(address(candle), tokenId);
        uint aid = candle.createAuction(address(nft), tokenId, block.number + 100, block.number + 150, address(weth));
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
	(address highest, uint amount) = candle.getHighestBid(aid);
	assertEq(highest, address(Alice));
	assertEq(amount, 1 ether);

	Alice.withdrawBid();
	assertEq(nft.balanceOf(address(Alice)), 1);
	assertEq(Alice.balance(), 9 ether);
	Bob.withdrawBid();
	assertEq(nft.balanceOf(address(Bob)), 0);
	assertEq(Bob.balance(), 10 ether);
    }

    function onERC721Received(address, address, uint256, bytes memory) public returns(bytes4) {
        return this.onERC721Received.selector;
    }
}
