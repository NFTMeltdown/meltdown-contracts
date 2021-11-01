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

    event AuctionCreated(uint256 auctionId, uint256 closingBlock, uint256 finalBlock, address bidToken);
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
        {
            keyHash = 0x6c3699283bda56ad74f6b855546325b68d482e983852a7a82979cc4807b641f4;
            fee = 0.1 * 10**18; // 0.1 LINK (Varies by network)
        }
    }

    struct Auction {
        address tokenAddress;
        uint256 tokenId;
        address seller;
        uint256 closingBlock;
        uint256 finalBlock;
        address bidToken;
        address currentHighestBidder;
        mapping(uint256 => address) highestBidderAtIndex;
        mapping(address => uint256) cumululativeBidFromBidder;
	uint256[] highestChangeAt;
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
        uint256 _closingBlock,
        uint256 _finalBlock,
        address _bidToken
    ) public returns (uint256) {
        require(IERC721(_tokenAddress).ownerOf(_tokenId) == msg.sender, "You are not the owner");
        // auction must last at least 50 blocks (~ 10 minutes)
        // require(_closingBlock > add(block.number, 50), "Too short");
        // require at least 20 (~240s) closing blocks
        uint256 closingWindow = sub(_finalBlock, _closingBlock);
        // require(closingWindow >= 20, "Closing window short");

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
        a.bidToken = _bidToken;

	// Plan to finalise the block straight afte rthe auction finishes
        blocksToFinaliseAuctions[add(_finalBlock, 1)].push(auctionId);
        emit AuctionCreated(auctionId, _closingBlock, _finalBlock, _bidToken);
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
	uint i;
        // Don't need to finalise auction anymore:w

	uint[] storage arr = blocksToFinaliseAuctions[a.finalBlock+1];
	while (arr[i] != auctionId) {
		i++;
	}
	arr[i] = arr[arr.length - 1];
        arr.pop();
        a.finalBlock = 0;
        IERC721(a.tokenAddress).safeTransferFrom(
            address(this),
            msg.sender,
            a.tokenId
        );
	// Finalise the auction
        emit AuctionFinalised(auctionId, address(0), 0);
    }

    function addToBid(uint256 auctionId, uint256 increaseBidBy) external {
        Auction storage a = idToAuction[auctionId];
        require(block.number <= a.finalBlock, "Auction is over");
        // If we are in regular time, aindex=0
        // Otherwise, start indexing from 1.
        uint256 aindex;
        if (block.number >= a.closingBlock) {
            aindex = block.number - a.closingBlock + 1;
        }
        uint256 balance = IERC20(a.bidToken).balanceOf(address(this));
        IERC20(a.bidToken).transferFrom(
            msg.sender,
            address(this),
            increaseBidBy
        );
        uint256 received = sub(
            IERC20(a.bidToken).balanceOf(address(this)),
            balance
        );

        a.cumululativeBidFromBidder[msg.sender] += received;

        if (msg.sender != a.currentHighestBidder) {
            if (
                a.cumululativeBidFromBidder[msg.sender] >
                a.cumululativeBidFromBidder[a.currentHighestBidder]
            ) {
                a.highestBidderAtIndex[aindex] = msg.sender;
                a.currentHighestBidder = msg.sender;
                emit BidIncreased(
                    auctionId,
                    aindex,
                    msg.sender,
                    increaseBidBy,
                    true
                );
                return;
            }
        }
        emit BidIncreased(auctionId, aindex, msg.sender, increaseBidBy, false);
    }

    function finaliseAuction(uint256 auctionId, uint256 randomness) internal {
        Auction storage a = idToAuction[auctionId];
        require(block.number > a.finalBlock, "Auction is not over");
	require(a.finalBlock != 0, "Auction already finalised");
        uint256 closing = add(
            randomness % sub(a.finalBlock, a.closingBlock),
            1
        );
        a.finalBlock = 0;
        // work backwards from the closing block until we reach a highest bidder
        for (uint256 b = closing + 1; b > 0; b--) {
            if (a.highestBidderAtIndex[b - 1] != address(0)) {
                a.currentHighestBidder = a.highestBidderAtIndex[b - 1];
                uint256 winningBidAmount = a.cumululativeBidFromBidder[
                    a.currentHighestBidder
                ];
                emit AuctionFinalised(
                    auctionId,
                    a.currentHighestBidder,
                    winningBidAmount
                );
                return;
            }
        }
        // there were no bids at all.
        // transfer NFT back to sender.
        emit AuctionFinalised(auctionId, address(0), 0);
    }

    function withdraw(uint256 auctionId) external {
        Auction storage a = idToAuction[auctionId];
        require(a.finalBlock == 0, "Auction not finalised");
        if (msg.sender != a.seller) {
            // sender won the auction, transfer them the NFT
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
                IERC20(a.bidToken).transferFrom(
                    address(this),
                    msg.sender,
                    senderLosingBidAmount
                );
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
                IERC20(a.bidToken).transferFrom(
                    address(this),
                    msg.sender,
                    winningBidAmount
                );
            }
        }
    }

    function checkUpkeep(bytes calldata /* checkData */)
        external override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        if (blocksToFinaliseAuctions[block.number].length > 0) {
            return (true, abi.encode(blocksToFinaliseAuctions[block.number]));
        } else {
            return (false, bytes(""));
        }
    }

    function performUpkeep(bytes calldata performData ) external override {
        uint256[] memory requestIdsToFinalise = abi.decode(performData, (uint256[]));
        require(
            LINK.balanceOf(address(this)) > fee * requestIdsToFinalise.length,
            "Not enough LINK"
        );
        for (uint256 i; i < requestIdsToFinalise.length; i++) {
            requestIdToAuction[requestRandomness(keyHash, fee)] = requestIdsToFinalise[i];
        }
        // delete blocksToFinaliseAuctions[blockNum];
    }

    function fulfillRandomness(bytes32 requestId, uint256 randomness)
        internal
        override
    {
        uint256 auctionToFinalise = requestIdToAuction[requestId];
        finaliseAuction(auctionToFinalise, randomness);
    }

    function manualFulfil(uint256 auctionToFinalise, uint256 randomness)
        external
        returns (uint256)
    {
        finaliseAuction(auctionToFinalise, randomness);
        return randomness;
    }

    function manualRequestRandomness(uint256 auctionToFinalise)
        external
    {
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
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
