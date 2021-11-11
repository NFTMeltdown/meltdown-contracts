#!/bin/bash

ME=0x4A9BffAB0b3758D0c03055Ff37d7D1E1B23fb849
NFT_CONTRACT=0x81319f7F729C9a9733b036258d523fC58CB3b0cD
APPROVE="approve(address,uint256)"
CREATE_AUCTION="createAuction(address,uint256,uint256,uint256,uint256)(uint256)"
echo "Approving $1 to spend NFT"
seth send --from $ME $NFT_CONTRACT $APPROVE $1 $2
BLK=$(seth block-number)
AUCTION_LENGTH=50
CLOSING_LENGTH=20
MIN_BID=0
echo $(($BLK + $AUCTION_LENGTH))
echo "Creating auction of length $AUCTION_LENGTH closing window length: $CLOSING_LENGTH"
seth send --from $ME $1 $CREATE_AUCTION $NFT_CONTRACT $2 $AUCTION_LENGTH $CLOSING_LENGTH $MIN_BID
