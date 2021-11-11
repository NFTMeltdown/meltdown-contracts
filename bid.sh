#!/bin/bash

ME=0xf66FA0E475eE6Cc73f9C1Fa7c537a052488Cc04B
NFT_CONTRACT=0x81319f7F729C9a9733b036258d523fC58CB3b0cD
MAXINT=0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
ADDTOBID="addToBid(uint256)"
echo "You have $(seth balance $ME) wei"
echo "Bidding $3 on auction $2"
seth send --value $3 --from $ME $1 $ADDTOBID $2