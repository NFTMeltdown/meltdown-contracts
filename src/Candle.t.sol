pragma solidity ^0.8.6;

import "ds-test/test.sol";

import "./utils/Hevm.sol";
import "./Candle.sol";
import "./TestNFT.sol";

interface WETH {
    function balanceOf(address) external returns (uint);
    function deposit() external payable;
}

contract CandleTest is DSTest {

    Hevm internal constant hevm = Hevm(HEVM_ADDRESS);

    Candle candle;
    TestNFT nft;
    WETH weth;
    
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
        weth.deposit{value: 1 ether}();
        uint tokenId = nft.mint(address(this));
        nft.approve(address(candle), tokenId);
        candle.createAuction(address(nft), tokenId, block.number + 100, block.number + 150, address(weth));
    }

    function test_create_and_bid() public {
        uint tokenId = nft.mint(address(this));
        nft.approve(address(candle), tokenId);
        candle.createAuction(address(nft), tokenId, block.number + 100, block.number + 150, address(weth));
        //candle.addToBid(tokenAddress, tokenId, increaseBidBy);
    }
}
