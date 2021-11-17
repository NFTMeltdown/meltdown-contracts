#!/bin/bash
NFT_CONTRACT=0xa1b028b06b1663c2e3ca6ccf0d2374d1d2edfc97
ABI="transferFrom(address,address,uint256)"
ME=0x4A9BffAB0b3758D0c03055Ff37d7D1E1B23fb849
echo "Sending ${NFT_CONTRACT} id $2 to $1"
seth send --status --from $ME $NFT_CONTRACT $ABI $ME $1 $2
