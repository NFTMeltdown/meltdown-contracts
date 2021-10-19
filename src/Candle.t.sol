pragma solidity ^0.8.6;

import "ds-test/test.sol";

import "./Candle.sol";

contract CandleTest is DSTest {
    Candle candle;

    function setUp() public {
        candle = new Candle();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
