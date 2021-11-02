#!/bin/bash

ME=0x4A9BffAB0b3758D0c03055Ff37d7D1E1B23fb849
NFT_CONTRACT=0xB2C7C58eD50cDD635cb2CB25336BF529e0B37599
WETH=0xd0A1E359811322d97991E03f863a0C30C2cF029C
APPROVE="approve(address,uint256)"
CREATE_AUCTION="createAuction(address,uint256,uint256,uint256,address)(uint256)"
echo "Approving $1 to spend NFT"
seth send --password password.txt $NFT_CONTRACT $APPROVE $1 $2
BLK=$(seth block-number)
CLOSING_BLOCK=10
FINAL_BLOCK=20
echo $(($BLK + $CLOSING_BLOCK))
echo "Creating auction of length closing: $CLOSING_BLOCK final: $FINAL_BLOCK"
seth send --password password.txt $1 $CREATE_AUCTION $NFT_CONTRACT $2 $(($BLK + $CLOSING_BLOCK)) $(($BLK + $FINAL_BLOCK)) $WETH
