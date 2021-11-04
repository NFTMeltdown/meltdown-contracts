#!/bin/bash

ME=0xf66FA0E475eE6Cc73f9C1Fa7c537a052488Cc04B
NFT_CONTRACT=0xB2C7C58eD50cDD635cb2CB25336BF529e0B37599
WETH=0xd0A1E359811322d97991E03f863a0C30C2cF029C
MAXINT=0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
APPROVE="approve(address,uint256)"
ADDTOBID="addToBid(uint256,uint256)"
echo "You have $(seth call $WETH "balanceOf(address)(uint256)" $ME) WETH"
:q
echo "Approving $1 to spend unlimited WETH"
seth send --password password.txt --from $ME $WETH $APPROVE $1 $MAXINT
echo "Bidding $3 on auction $2"
seth send --password password.txt --from $ME $1 $ADDTOBID $2 $3
