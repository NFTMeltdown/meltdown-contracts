pragma solidity ^0.8.6;

import "ds-math/math.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Candle is VRFConsumerBase, DSMath {
    bytes32 internal keyHash;
    uint256 internal fee;
    uint256 public randomResult;

    mapping (bytes32 => Auction) hashToAuction;
    mapping (bytes32 => bytes32) requestIdToAuction;
    mapping (uint => bytes32[]) blocksToFinaliseAuctions;

    // VRFCoordinator
    // LINK Token
    constructor()
    VRFConsumerBase(
        0xdD3782915140c8f3b190B5D67eAc6dc5760C46E9, 
        0xa36085F69e2889c224210F603D836748e7dC0088
        ) {
        {
            keyHash = 0x6c3699283bda56ad74f6b855546325b68d482e983852a7a82979cc4807b641f4;
            fee = 0.1 * 10 ** 18; // 0.1 LINK (Varies by network)
        }
    }

    struct Auction {
        address tokenAddress;
        uint tokenId;
        address seller;
        uint closingBlock;
        uint finalBlock;
        address bidToken;
        // the first elements of bids will be updated during
        // regular bidding time, the rest will be populated during bidding window. 
        address currentHighestBidder;
        mapping (uint => address) highestBidderAtIndex;
        mapping (address => uint) cumululativeBidFromBidder;
    }

    modifier canBe64(uint256 _value) {
        require(_value < 18446744073709551615);
        _;
    }
    modifier canBe128(uint256 _value) {
        require(_value < 340282366920938463463374607431768211455);
        _;
    }

    /// @dev Creates and begins a new auction
    /// @param _tokenId - NFT token id to be auctioned
    function createAuction(
        address _tokenAddress,
        uint _tokenId,
        uint _closingBlock,
        uint _finalBlock,
        address _bidToken
    )
        public 
    {
        require(IERC721(_tokenAddress).ownerOf(_tokenId) == msg.sender);
        // auction must last at least 50 blocks (10 minutes)
        require(_closingBlock > add(block.number, 50));
        // require at least 20 (~240s) closing blocks
        uint closingWindow = sub(_finalBlock, _closingBlock);
        require(closingWindow >= 20);

        IERC721(_tokenAddress).safeTransferFrom(msg.sender, address(this), _tokenId);

        bytes32 auctionId = keccak256(abi.encodePacked(_tokenId, _tokenAddress));
        Auction storage a = hashToAuction[auctionId];
        a.tokenAddress = _tokenAddress;
        a.tokenId = _tokenId;
        a.seller = msg.sender;
        a.closingBlock = _closingBlock;
        a.finalBlock = _finalBlock;
        a.bidToken = _bidToken;

        blocksToFinaliseAuctions[add(_finalBlock, 1)].push(auctionId);
    }

    function cancelAuction(
        address tokenAddress,
        uint tokenId
    ) external {
        Auction storage a = hashToAuction[keccak256(abi.encodePacked(tokenId, tokenAddress))];
        require(msg.sender == a.seller);
        IERC721(tokenAddress).safeTransferFrom(address(this), msg.sender, tokenId);
    }

    function addToBid(
        address tokenAddress,
        uint tokenId,
        uint increaseBidBy
    )
        public
    {
        Auction storage a = hashToAuction[keccak256(abi.encodePacked(tokenId, tokenAddress))];
        require(block.number <= a.finalBlock, "Auction is over");
        // If we are in regular time 
        uint aindex;
        if (block.number > a.closingBlock) {
            aindex = block.number - a.closingBlock;
        }
        uint balance = IERC20(a.bidToken).balanceOf(address(this)); 
        IERC20(a.bidToken).transferFrom(msg.sender, address(this), increaseBidBy);
        uint received = sub(IERC20(a.bidToken).balanceOf(address(this)), balance);

        a.cumululativeBidFromBidder[msg.sender] += received;

        if (msg.sender != a.currentHighestBidder) {
            if (a.cumululativeBidFromBidder[msg.sender] > a.cumululativeBidFromBidder[a.currentHighestBidder]) {
                a.highestBidderAtIndex[aindex] = msg.sender;
                a.currentHighestBidder = msg.sender;
            }
        }
    }

    function finaliseAuction(
	    bytes32 auctionId,
	    uint256 randomness
    ) internal {
        Auction storage a  = hashToAuction[auctionId];
        require(block.number > a.finalBlock);
        uint closing = randomness % add(sub(a.finalBlock, a.closingBlock), 1);
        // work backwards from the closing block until we reach a highest bidder
        for (uint b = closing; b >= 0; b--) {
            if (a.highestBidderAtIndex[b] != address(0)) {
                // transfer nft to auction winner
                IERC721(a.tokenAddress).safeTransferFrom(address(this), a.highestBidderAtIndex[b], a.tokenId);
                // send eth back to auction starter
                IERC20(a.bidToken).transferFrom(address(this), a.seller, a.cumululativeBidFromBidder[a.highestBidderAtIndex[b]]);
                return;
            }
        }
    }

    function checkUpkeep(
        bytes calldata checkData
    ) external 
    returns (
        bool upkeepNeeded,
        bytes memory performData
    ) {
        if (blocksToFinaliseAuctions[block.number].length > 0) {
            return (true, abi.encode(block.number));
        } else {
            return (false, bytes(""));
        }
    }

    function performUpkeep(
        bytes calldata performData
    ) external {
        uint blockNum = abi.decode(performData, (uint));
        require(LINK.balanceOf(address(this)) >= fee * blocksToFinaliseAuctions[blockNum].length, "Not enough LINK");
        for (uint i; i < blocksToFinaliseAuctions[blockNum].length; i++) {
            requestIdToAuction[requestRandomness(keyHash, fee)] = blocksToFinaliseAuctions[blockNum][i];
        }
        delete blocksToFinaliseAuctions[blockNum];
    }

    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
	    bytes32 auctionToFinalise = requestIdToAuction[requestId];
	    finaliseAuction(auctionToFinalise, randomness);
    }

    function manualFulfil(bytes32 auctionToFinalise) external {
        finaliseAuction(auctionToFinalise, uint(blockhash(block.number -1)));
    }
}
