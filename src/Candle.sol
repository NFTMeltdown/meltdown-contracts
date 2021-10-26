pragma solidity ^0.8.6;

import "ds-math/math.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract Candle is VRFConsumerBase, DSMath, IERC721Receiver {
    using Counters for Counters.Counter;

    Counters.Counter private auctionIdCounter;

    bytes32 internal keyHash;
    uint256 internal fee;
    uint256 public randomResult;

    event AuctionCreated(uint,uint,uint,address);
    event BidIncreased(uint,address,uint,bool);
    event AuctionFinalised(uint,address,uint);

    mapping (uint => Auction) idToAuction;
    mapping (bytes32 => uint) requestIdToAuction;
    mapping (uint => uint[]) blocksToFinaliseAuctions;

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
        // the first element of bids will be updated during
        // regular bidding time, the following elements will increase during bidding window.
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
    function createAuction (
        address _tokenAddress,
        uint _tokenId,
        uint _closingBlock,
        uint _finalBlock,
        address _bidToken
    )
        public
	returns (uint)
    {
        require(IERC721(_tokenAddress).ownerOf(_tokenId) == msg.sender);
        // auction must last at least 50 blocks (10 minutes)
        require(_closingBlock > add(block.number, 50));
        // require at least 20 (~240s) closing blocks
        uint closingWindow = sub(_finalBlock, _closingBlock);
        require(closingWindow >= 20);

        IERC721(_tokenAddress).safeTransferFrom(msg.sender, address(this), _tokenId);

        uint auctionId = auctionIdCounter.current();
	auctionIdCounter.increment();
        Auction storage a = idToAuction[auctionId];
        a.tokenAddress = _tokenAddress;
        a.tokenId = _tokenId;
        a.seller = msg.sender;
        a.closingBlock = _closingBlock;
        a.finalBlock = _finalBlock;
        a.bidToken = _bidToken;

        blocksToFinaliseAuctions[add(_finalBlock, 1)].push(auctionId);
        emit AuctionCreated(auctionId, _closingBlock, _finalBlock, _bidToken);
	return auctionId;
    }

    function getHighestBid(
	    uint auctionId
    )
    view
    public
    returns (address, uint)
    {
	    Auction storage a = idToAuction[auctionId];
	    return (a.currentHighestBidder, a.cumululativeBidFromBidder[a.currentHighestBidder]);
    }

    function cancelAuction(
	    uint auctionId
    ) external {
        Auction storage a = idToAuction[auctionId];
        require(msg.sender == a.seller);
        a.finalBlock = 0;
        IERC721(a.tokenAddress).safeTransferFrom(address(this), msg.sender, a.tokenId);
    }

    function addToBid(
	uint auctionId,
        uint increaseBidBy
    )
        external
    {
        Auction storage a = idToAuction[auctionId];
        require(block.number <= a.finalBlock, "Auction is over");
        // If we are in regular time, aindex=0
        // Otherwise, start indexing from 1.
        uint aindex;
        if (block.number >= a.closingBlock) {
            aindex = block.number - a.closingBlock + 1;
        }
        uint balance = IERC20(a.bidToken).balanceOf(address(this));
        IERC20(a.bidToken).transferFrom(msg.sender, address(this), increaseBidBy);
        uint received = sub(IERC20(a.bidToken).balanceOf(address(this)), balance);

        a.cumululativeBidFromBidder[msg.sender] += received;

        if (msg.sender != a.currentHighestBidder) {
		if (a.cumululativeBidFromBidder[msg.sender] > a.cumululativeBidFromBidder[a.currentHighestBidder]) {
			a.highestBidderAtIndex[aindex] = msg.sender;
			a.currentHighestBidder = msg.sender;
			emit BidIncreased(auctionId, msg.sender, increaseBidBy, true);
            }
        }
	emit BidIncreased(auctionId, msg.sender, increaseBidBy, false);
    }

    function finaliseAuction(
	    uint auctionId,
	    uint256 randomness
    ) internal {
        Auction storage a  = idToAuction[auctionId];
        require(block.number > a.finalBlock, "Auction is not over");
        uint closing = add(randomness % sub(a.finalBlock, a.closingBlock), 1);
	a.finalBlock = 0;
        // work backwards from the closing block until we reach a highest bidder
        for (uint b = closing+1; b > 0; b--) {
            if (a.highestBidderAtIndex[b-1] != address(0)) {
		a.currentHighestBidder = a.highestBidderAtIndex[b-1];
		uint winningBidAmount = a.cumululativeBidFromBidder[a.currentHighestBidder];
		emit AuctionFinalised(auctionId, a.currentHighestBidder, winningBidAmount);
		return;
            }
        }
	// there were no bids at all. 
	// transfer NFT back to sender.
	emit AuctionFinalised(auctionId, address(0), 0);
    }

    function withdraw(
	    uint auctionId
    )
    external
    {
	    Auction storage a  = idToAuction[auctionId];
	    require(a.finalBlock == 0, "Auction not finalised");
	    if (msg.sender != a.seller) {
		    // sender won the auction, transfer them the NFT
		    // otherwise sender lost, transfer them their money back.
		    if (msg.sender == a.currentHighestBidder) {
			    IERC721(a.tokenAddress).safeTransferFrom(address(this), msg.sender, a.tokenId);
		    } else {
			    uint senderLosingBidAmount = a.cumululativeBidFromBidder[msg.sender];
			    IERC20(a.bidToken).transferFrom(address(this), msg.sender, senderLosingBidAmount);
		    }
	    } else {
		    // if there were no bids, return nft
		    // otherwise return proceeds.
		    if (a.currentHighestBidder == address(0)) {
			    IERC721(a.tokenAddress).safeTransferFrom(address(this), msg.sender, a.tokenId);
		    } else {
			    uint winningBidAmount = a.cumululativeBidFromBidder[a.currentHighestBidder];
			    IERC20(a.bidToken).transferFrom(address(this), msg.sender, winningBidAmount);
		    }
	    }
    }

    function checkUpkeep(
        bytes calldata checkData
    ) 
    external 
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
	    uint auctionToFinalise = requestIdToAuction[requestId];
	    finaliseAuction(auctionToFinalise, randomness);
    }

    function manualFulfil(uint auctionToFinalise, uint randomness) external returns (uint) {
	finaliseAuction(auctionToFinalise, randomness);
	return randomness;
    }

    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns(bytes4) {
        return this.onERC721Received.selector;
    }

}
