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
    event AuctionFinalised(uint256 auctionId, address winner, uint256 amount, uint256 blockFinalised);
    event BidIncreased(uint256 auctionId, uint256 aindex, address bidder, uint256 amount, bool newHighestBidder);

    mapping(uint256 => Auction) public idToAuction;
    mapping(bytes32 => uint256) public requestIdToAuction;
    mapping(uint256 => uint256[]) public blocksToFinaliseAuctions;

    constructor()
        VRFConsumerBase(
            0xdD3782915140c8f3b190B5D67eAc6dc5760C46E9, // VRFCoordinator
            0xa36085F69e2889c224210F603D836748e7dC0088 // LINK Token Address
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

    //////////////////////////////////////////////////////
    ////////////   STATE-CHANGING FUNCTIONS   ////////////
    //////////////////////////////////////////////////////

    /// @notice Create an auction with an approved ERC721 and parameters
    /// @param _tokenAddress ERC721 address
    /// @param _tokenId ERC721 tokenId
    /// @param _auctionLengthBlocks length of auction in blocks
    /// @param _closingLengthBlocks length of closing window in blocks
    /// @param _minBid address(0) will be set to have this bid
    /// @return ID of auction
    function createAuction(
        address _tokenAddress,
        uint256 _tokenId,
        uint256 _auctionLengthBlocks,
        uint256 _closingLengthBlocks,
        uint256 _minBid
    ) public returns (uint256) {
        require(
            IERC721(_tokenAddress).ownerOf(_tokenId) == msg.sender,
            "You are not the owner"
        );
        // Auction must last at least 50 blocks (~ 10 minutes)
        require(_auctionLengthBlocks > 50, "Auction length too short");
        // Closing length must be 20% of total length
        require(_closingLengthBlocks > 10, "Closing length too short");
        uint256 _closingBlock = sub( add(block.number, _auctionLengthBlocks), _closingLengthBlocks);
        uint256 _finalBlock = add(block.number, _auctionLengthBlocks);

        // Transfer the NFT from the seller to the contract
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

        // Set address(0) to have the minimum bid.
        // So winner must be > _minBid to win auction.
        a.cumululativeBidFromBidder[a.currentHighestBidder] = _minBid;

        // Schedule to finalise the block straight after the auction finishes
        blocksToFinaliseAuctions[add(_finalBlock, 1)].push(auctionId);
        emit AuctionCreated(auctionId, _closingBlock, _finalBlock);
        return auctionId;
    }

    /// @notice Cancel an auction 
    /// @param auctionId ID of auction
    /// @dev Requires the highest current bid to be below the min bid. 
    function cancelAuction(uint256 auctionId) external {
        Auction storage a = idToAuction[auctionId];
        require(msg.sender == a.seller);
        // Cannot cancel an auction while it is in finalisation phase.
        require( a.currentHighestBidder == address(0), "Highest bid above min. Can't cancel.");
        // Don't need to finalise auction anymore
        // We can remove it from the schedule Chainlink Keeper block
        uint256 i;
        uint256[] storage arr = blocksToFinaliseAuctions[a.finalBlock + 1];
        while (arr[i] != auctionId) {
            i++;
        }
        arr[i] = arr[arr.length - 1];
        arr.pop();
        a.finalBlock = 0;
        emit AuctionFinalised(auctionId, address(0), 0, 0);
    }

    /// @notice Add to the msg.sender current bid. 
    /// @param auctionId ID of auction
    /// @dev Doesn't necessarily have to be greater than the current highest bid. 
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

        // If the bid creates a new highest bidder
        if ( msg.sender != a.currentHighestBidder &&
         (a.cumululativeBidFromBidder[msg.sender] > a.cumululativeBidFromBidder[a.currentHighestBidder])) {
            a.highestBidderAtIndex[aindex] = msg.sender;
            a.currentHighestBidder = msg.sender;
            a.highestBidderChangedAt.push(aindex);
            emit BidIncreased(auctionId, aindex, msg.sender, msg.value, true);
            return;
        }
        emit BidIncreased(auctionId, aindex, msg.sender, msg.value, false);
    }

    /// @notice Called by Chainlink VRF callback function to finalise an auction. 
    /// @param auctionId ID of auction
    /// @param randomness Verifiable random uint256 from Chainlink. 
    /// @dev This function should only be called by a Chainlink node. 
    function finaliseAuction(uint256 auctionId, uint256 randomness) internal {
        Auction storage a = idToAuction[auctionId];
        require(block.number > a.finalBlock, "Auction is not over");
        require(a.finalBlock != 0, "Auction already finalised");
        uint256 closing_index = add( randomness % sub(a.finalBlock, a.closingBlock), 1);
        a.finalBlock = 0;
        // Work backwards from the last highestBidderChangedAt until it is below the lastBlock
        for (uint256 b = a.highestBidderChangedAt.length; b > 0; b--) {
            if (a.highestBidderChangedAt[b - 1] <= closing_index) {
                a.currentHighestBidder = a.highestBidderAtIndex[ a.highestBidderChangedAt[b - 1] ];
                uint256 winningBidAmount = a.cumululativeBidFromBidder[ a.currentHighestBidder ];

                emit AuctionFinalised(
                    auctionId,
                    a.currentHighestBidder,
                    winningBidAmount,
                    add(sub(closing_index, 1), a.closingBlock)
                );
                return;
            }
        }
        // There were no bids at all.
        emit AuctionFinalised(
            auctionId,
            address(0),
            0,
            add(sub(closing_index, 1), a.closingBlock)
        );
    }

    /// @notice Withdraw the msg.sender's result of an auction. ERC721/ETH
    /// @param auctionId ID of auction
    function withdraw(uint256 auctionId) external {
        Auction storage a = idToAuction[auctionId];
        require(a.finalBlock == 0, "Auction not finalised");
        if (msg.sender != a.seller) {
            // If sender won the auction, transfer them the NFT
            // Otherwise sender lost, transfer them their money back.
            if (msg.sender == a.currentHighestBidder) {
                IERC721(a.tokenAddress).safeTransferFrom(
                    address(this),
                    msg.sender,
                    a.tokenId
                );
            } else {
                uint256 senderLosingBidAmount = a.cumululativeBidFromBidder[ msg.sender ];
                a.cumululativeBidFromBidder[msg.sender] = 0;
                (bool success, ) = msg.sender.call{ value: senderLosingBidAmount }("");
                require(success, "Transfer failed.");
            }
        } else {
            // If there were no bids, return nft
            // Otherwise return proceeds.
            if (a.currentHighestBidder == address(0)) {
                IERC721(a.tokenAddress).safeTransferFrom(
                    address(this),
                    msg.sender,
                    a.tokenId
                );
            } else {
                uint256 winningBidAmount = a.cumululativeBidFromBidder[ a.currentHighestBidder ];
                a.cumululativeBidFromBidder[a.currentHighestBidder] = 0;
                (bool success, ) = msg.sender.call{value: winningBidAmount}("");
                require(success, "Transfer failed.");
            }
        }
    }

    //////////////////////////////////////////////////////
    //////////////   CHAINLINK FUNCTIONS   ///////////////
    //////////////////////////////////////////////////////

    /// @dev Should be treated like a view function. 
    function checkUpkeep(
        bytes calldata /*checkData*/
    ) external override returns (bool upkeepNeeded, bytes memory performData) {
        // Check whether an auction needs finalising in the last 100 blocks
        for (uint256 i; i < 100; i++) {
            if (blocksToFinaliseAuctions[block.number - i].length > 0) {
                return (
                    true,
                    abi.encode( block.number - i, blocksToFinaliseAuctions[block.number - i])
                );
            }
        }
        return (false, bytes(""));
    }

    /// @notice Called by a Keeper node if an auction is finished (checkUpkeep==true)
    /// @dev Requests a random number from CL network. 
    function performUpkeep(bytes calldata performData) external override {
        (uint256 blockNum, uint256[] memory requestIdsToFinalise) = abi.decode(
            performData,
            (uint256, uint256[])
        );
        require(
            LINK.balanceOf(address(this)) > fee * requestIdsToFinalise.length,
            "Not enough LINK"
        );
        for (uint256 i; i < requestIdsToFinalise.length; i++) {
            requestIdToAuction[ requestRandomness(keyHash, fee) ] = requestIdsToFinalise[i];
        }
        delete blocksToFinaliseAuctions[blockNum];
    }

    /// @notice Chainlink VRF callback function that finalises an auction
    /// @dev Should only be able to be called by CL
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

    function manualRequestRandomness(uint256 auctionToFinalise) external {
        require(msg.sender == owner, "Only owner can manualRequestRandomness");
        require(LINK.balanceOf(address(this)) > fee, "Not enough LINK");
        requestIdToAuction[requestRandomness(keyHash, fee)] = auctionToFinalise;
    }

    //////////////////////////////////////////////////////
    /////////////////   VIEW FUNCTIONS   /////////////////
    //////////////////////////////////////////////////////

    function currentCumulativeBid(uint256 auctionId, address bidder)
        external
        view
        returns (uint256)
    {
        Auction storage a = idToAuction[auctionId];
        return a.cumululativeBidFromBidder[bidder];
    }

    // Convenience getter methods to get everything about an auction
    function getAuction(uint256 auctionId)
        public
        view
        returns ( address, uint256, address, uint256, uint256, address, uint256[] memory)
    {
        Auction storage a = idToAuction[auctionId];
        return (
            a.tokenAddress,
            a.tokenId,
            a.seller,
            a.closingBlock,
            a.finalBlock,
            a.currentHighestBidder,
            a.highestBidderChangedAt
        );
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

    function getAuctionHighestBidderAtIndex(uint256 auctionId, uint256 index)
        public
        view
        returns (address)
    {
        Auction storage a = idToAuction[auctionId];
        return a.highestBidderAtIndex[index];
    }

    function getCumulativeBidFromBidder(uint256 auctionId, address bidder)
        public
        view
        returns (uint256)
    {
        Auction storage a = idToAuction[auctionId];
        return a.cumululativeBidFromBidder[bidder];
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
