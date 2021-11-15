#!/bin/bash

ME=0xf66FA0E475eE6Cc73f9C1Fa7c537a052488Cc04B
NFT_CONTRACT=0xa1b028b06b1663C2E3CA6CcF0D2374D1D2eDFC97
MAXINT=0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
ADDTOBID="addToBid(uint256)"
echo "You have $(seth balance $ME) wei"
echo "Bidding $3 on auction $2"
seth send --value $3 --from $ME $1 $ADDTOBID $2