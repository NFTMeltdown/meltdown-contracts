#!/bin/bash

NFT_CONTRACT=0xa1b028b06b1663C2E3CA6CcF0D2374D1D2eDFC97
MAXINT=0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
ADDTOBID="addToBid(uint256)"
echo "You have $(seth balance $4) wei"
echo "Bidding $3 on auction $2"
seth send --value $3 --from $4 $1 $ADDTOBID $2
