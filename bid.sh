#!/bin/bash

ME=0xf66FA0E475eE6Cc73f9C1Fa7c537a052488Cc04B
NFT_CONTRACT=0x757B6E1496292d80287F270D025Ba953ae7Ae6F9
MAXINT=0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
ADDTOBID="addToBid(uint256)"
echo "You have $(seth balance $ME) wei"
echo "Bidding $3 on auction $2"
seth send --value $3 --from $ME $1 $ADDTOBID $2