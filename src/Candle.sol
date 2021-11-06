pragma solidity ^0.8.6;

import "ds-math/math.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/// @title A candle-auction contract for ERC721 tokens.
/// @author calebcheng00 and VasilyGerrans
contract Candle is KeeperCompatibleInterface, VRFConsumerBase, DSMath, IERC721Receiver {
    using Counters for Counters.Counter;
    Counters.Counter private auctionIdCounter;

    bytes32 internal keyHash;
    uint256 internal fee;
    uint256 public randomResult;
    address owner;

    event AuctionCreated(uint256 auctionId, uint256 closingBlock, uint256 finalBlock);
    event AuctionFinalised(uint256 auctionId, address winner, uint256 amount);
    event BidIncreased(uint256 auctionId, uint256 aindex, address bidder, uint256 amount, bool newHighestBidder);

    mapping(uint256 => Auction) public idToAuction;
    mapping(bytes32 => uint256) public requestIdToAuction;
    mapping(uint256 => uint256[]) public blocksToFinaliseAuctions;

    constructor()
        VRFConsumerBase(
            0xdD3782915140c8f3b190B5D67eAc6dc5760C46E9, // VRFCoordinator
            0xa36085F69e2889c224210F603D836748e7dC0088  // LINK Token Address
        )
    {
            keyHash = 0x6c3699283bda56ad74f6b855546325b68d482e983852a7a82979cc4807b641f4;
            fee = 0.1 * 10**18; // 0.1 LINK (Varies by network)
	    owner = msg.sender;
    }

    struct Auction {
        address tokenAddress;
        uint256 tokenId;
        address seller;
        uint256 closingBlock;
        uint256 finalBlock;
        address currentHighestBidder;
	uint256[] highestBidderChangedAt;
        mapping(uint256 => address) highestBidderAtIndex;
        mapping(address => uint256) cumululativeBidFromBidder;
    }


    modifier canBe64(uint256 _value) {
        require(_value < 18446744073709551615);
        _;
    }
    modifier canBe128(uint256 _value) {
        require(_value < 340282366920938463463374607431768211455);
        _;
    }

    function createAuction(
        address _tokenAddress,
        uint256 _tokenId,
        uint256 _auctionLengthBlocks,
        uint256 _closingLengthBlocks,
	uint256 _minBid
    ) public returns (uint256) {
        require(IERC721(_tokenAddress).ownerOf(_tokenId) == msg.sender, "You are not the owner");
        // auction must last at least 50 blocks (~ 10 minutes)
        // require(_closingBlock > add(block.number, 50), "Too short");
        // require at least 20 (~240s) closing blocks
        // uint256 closingWindow = sub(_finalBlock, _closingBlock);
        // require(closingWindow >= 20, "Closing window short");
	require(_auctionLengthBlocks > _closingLengthBlocks, "Invalid length");
	uint _closingBlock = sub(add(block.number, _auctionLengthBlocks), _closingLengthBlocks);
	uint _finalBlock = add(block.number, _auctionLengthBlocks);

        IERC721(_tokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _tokenId
        );

        uint256 auctionId = auctionIdCounter.current();
        auctionIdCounter.increment();
        Auction storage a = idToAuction[auctionId];
        a.tokenAddress = _tokenAddress;
        a.tokenId = _tokenId;
        a.seller = msg.sender;
        a.closingBlock = _closingBlock;
        a.finalBlock = _finalBlock;
	a.cumululativeBidFromBidder[address(0)] = _minBid;

	// Plan to finalise the block straight afte rthe auction finishes
        blocksToFinaliseAuctions[add(_finalBlock, 1)].push(auctionId);
        emit AuctionCreated(auctionId, _closingBlock, _finalBlock);
        return auctionId;
    }

    function getHighestBid(uint256 auctionId)
        public
        view
        returns (address, uint256)
    {
        Auction storage a = idToAuction[auctionId];
        return (
            a.currentHighestBidder,
            a.cumululativeBidFromBidder[a.currentHighestBidder]
        );
    }

    function cancelAuction(uint256 auctionId) external {
        Auction storage a = idToAuction[auctionId];
        require(msg.sender == a.seller);
	// Cannot cancel an auction while it is in finalisation phase.
        require(block.number < a.closingBlock);
        // Don't need to finalise auction anymore
	uint i;
	uint[] storage arr = blocksToFinaliseAuctions[a.finalBlock+1];
	while (arr[i] != auctionId) {
		i++;
	}
	arr[i] = arr[arr.length - 1];
        arr.pop();
        a.finalBlock = 0;
	a.currentHighestBidder = address(0);
	// Finalise the auction
        emit AuctionFinalised(auctionId, address(0), 0);
    }

    function currentCumulativeBid(uint256 auctionId, address bidder) external view returns (uint256) {
	    Auction storage a = idToAuction[auctionId];
	    return a.cumululativeBidFromBidder[bidder];
    }

    function addToBid(uint256 auctionId) external payable {
        Auction storage a = idToAuction[auctionId];
        require(block.number <= a.finalBlock, "Auction is over");
	require(msg.sender != a.seller, "You are the seller");
        // If we are in regular time, aindex=0
        // Otherwise, start indexing from 1.
        uint256 aindex;
        if (block.number >= a.closingBlock) {
            aindex = block.number - a.closingBlock + 1;
        }

        a.cumululativeBidFromBidder[msg.sender] += msg.value;

        if (msg.sender != a.currentHighestBidder && (a.cumululativeBidFromBidder[msg.sender] > a.cumululativeBidFromBidder[a.currentHighestBidder])) {
		a.highestBidderAtIndex[aindex] = msg.sender;
		a.currentHighestBidder = msg.sender;
		a.highestBidderChangedAt.push(aindex);
		emit BidIncreased(
		    auctionId,
		    aindex,
		    msg.sender,
		    msg.value,
		    true
		);
		return;
        }
        emit BidIncreased(auctionId, aindex, msg.sender, msg.value, false);
    }

    function finaliseAuction(uint256 auctionId, uint256 randomness) internal {
        Auction storage a = idToAuction[auctionId];
        require(block.number > a.finalBlock, "Auction is not over");
	require(a.finalBlock != 0, "Auction already finalised");
        uint256 closing_index = add(
            randomness % sub(a.finalBlock, a.closingBlock),
            1
        );
        a.finalBlock = 0;
        // work backwards from the last highestBidderChangedAt until it is below the lastBlock
	for (uint b = a.highestBidderChangedAt.length; b > 0; b--) {
		if (a.highestBidderChangedAt[b-1] <= closing_index) {
			a.currentHighestBidder = a.highestBidderAtIndex[a.highestBidderChangedAt[b-1]];
			uint256 winningBidAmount = a.cumululativeBidFromBidder[a.currentHighestBidder];
			emit AuctionFinalised(
			    auctionId,
			    a.currentHighestBidder,
			    winningBidAmount
			);
			return;
		}
	}
        // there were no bids at all.
        emit AuctionFinalised(auctionId, address(0), 0);
    }

    function withdraw(uint256 auctionId) external {
        Auction storage a = idToAuction[auctionId];
        require(a.finalBlock == 0, "Auction not finalised");
        if (msg.sender != a.seller) {
            // if sender won the auction, transfer them the NFT
            // otherwise sender lost, transfer them their money back.
            if (msg.sender == a.currentHighestBidder) {
                IERC721(a.tokenAddress).safeTransferFrom(
                    address(this),
                    msg.sender,
                    a.tokenId
                );
            } else {
                uint256 senderLosingBidAmount = a.cumululativeBidFromBidder[
                    msg.sender
                ];
                a.cumululativeBidFromBidder[msg.sender] = 0;
		(bool success, ) = msg.sender.call{value:senderLosingBidAmount}("");
		require(success, "Transfer failed.");
            }
        } else {
            // if there were no bids, return nft
            // otherwise return proceeds.
            if (a.currentHighestBidder == address(0)) {
                IERC721(a.tokenAddress).safeTransferFrom(
                    address(this),
                    msg.sender,
                    a.tokenId
                );
            } else {
                uint256 winningBidAmount = a.cumululativeBidFromBidder[
                    a.currentHighestBidder
                ];
                a.cumululativeBidFromBidder[a.currentHighestBidder] = 0;
		(bool success, ) = msg.sender.call{value:winningBidAmount}("");
		require(success, "Transfer failed.");
            }
        }
    }

    // Convenience getter methods to get everything about an auction
    function getAuction(uint auctionId) public view returns (address,uint,address,uint,uint,address,uint[] memory) {
	    Auction storage a = idToAuction[auctionId];
	    return (a.tokenAddress, a.tokenId, a.seller, a.closingBlock, a.finalBlock, a.currentHighestBidder, a.highestBidderChangedAt);
    }

    function getAuctionHighestBidderAtIndex(uint auctionId, uint index) public view returns (address) {
	    Auction storage a = idToAuction[auctionId];
	    return a.highestBidderAtIndex[index];
    }
    function getCumulativeBidFromBidder(uint auctionId, address bidder) public view returns (uint) {
	    Auction storage a = idToAuction[auctionId];
	    return a.cumululativeBidFromBidder[bidder];
    }

    function checkUpkeep(bytes calldata checkData)
        external override
        returns (bool upkeepNeeded, bytes memory performData)
    {
	// check whether an auction needs finalising in the last 100 blocks
	for (uint i; i < 100; i++) {
		if (blocksToFinaliseAuctions[block.number-i].length > 0) {
		    return (true, abi.encode(block.number-i, blocksToFinaliseAuctions[block.number-i]));
		}
	}
	return (false, bytes(""));
    }

    function performUpkeep(bytes calldata performData) external override {
        (uint256 blockNum, uint256[] memory requestIdsToFinalise) = abi.decode(performData, (uint, uint256[]));
        require(
            LINK.balanceOf(address(this)) > fee * requestIdsToFinalise.length,
            "Not enough LINK"
        );
        for (uint256 i; i < requestIdsToFinalise.length; i++) {
            requestIdToAuction[requestRandomness(keyHash, fee)] = requestIdsToFinalise[i];
        }
        delete blocksToFinaliseAuctions[blockNum];
    }

    function fulfillRandomness(bytes32 requestId, uint256 randomness)
        internal
        override
    {
        finaliseAuction(requestIdToAuction[requestId], randomness);
    }

    function manualFulfil(uint256 auctionToFinalise, uint256 randomness)
        external
        returns (uint256)
    {
	require(msg.sender == owner, "Only owner can manualFulfil");
        finaliseAuction(auctionToFinalise, randomness);
        return randomness;
    }

    function manualRequestRandomness(uint256 auctionToFinalise)
        external
    {
	require(msg.sender == owner, "Only owner can manualRequestRandomness");
        require(
            LINK.balanceOf(address(this)) > fee,
            "Not enough LINK"
        );
	requestIdToAuction[requestRandomness(keyHash, fee)] = auctionToFinalise;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public pure virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
