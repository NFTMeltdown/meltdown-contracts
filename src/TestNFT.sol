pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract TestNFT is ERC721 {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenId;
    constructor() ERC721("TestNFT", "TNFT") {
    }
    // returns tokenid
    function mint(address sender) public returns (uint256) {
        _tokenId.increment();
        uint256 newItemId = _tokenId.current();
        _mint(sender, newItemId);
        return newItemId;
    }
}
