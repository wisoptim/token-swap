
# How to deploy and verify #

```shell
npm install
npx hardhat compile
npx hardhat run scripts/deploy.js --network bsctestnet
npx hardhat verify --network bscmainnet 0x85a201495902f3D439763Ab8430f117acEf4d3f3
```

# How to run #
1. Set addresses of the tokens using:
`setTokens(Titano.address, Titano2.address);`

2. Allow swapping:
`setIsSwapStarted(true);`

3. Transfer some funds of Token 2 to the swap contract. This is required to allow the swap contract transfer Token 2 to user in exchange to Token 1 with 1:1 ration
