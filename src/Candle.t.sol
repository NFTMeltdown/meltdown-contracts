pragma solidity ^0.8.6;

import "ds-test/test.sol";

import "./Candle.sol";
import "./TestNFT.sol";


contract CandleTest is DSTest {
    Candle candle;
    TestNFT nft;
    
    address WETH = 0xd0A1E359811322d97991E03f863a0C30C2cF029C;

    function setUp() public {
        candle = new Candle();
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
        nft.mint(address(this));
        // candle.createAuction(AAVEGOTCHI_KOVAN, 1835, block.number + 100, block.number + 150, WETH);
    }
}
