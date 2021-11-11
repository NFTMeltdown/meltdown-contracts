pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract TestNFT is ERC721URIStorage {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenId;

    function _baseURI() internal view override returns (string memory) {
        return "ipfs://";
    }

    constructor() ERC721("piccAIso", "CPPN") {
    }


    // returns tokenid
    function mint(address sender, string memory metadataURI) public returns (uint256) {
        _tokenId.increment();
        uint256 newItemId = _tokenId.current();
        _mint(sender, newItemId);
        _setTokenURI(newItemId, metadataURI);
        return newItemId;
    }
}
