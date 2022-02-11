const { ethers, upgrades } = require("hardhat");
const { expect } = require("chai");

describe("Titano rebase", function () {
    let owner, user1, autoLiquidityReceiver, TreasuryReceiver, RiskFreeValueReceiver, dex, others;
    let titano,titano2, titanoSwap, contractSwapAsUser1, contract1AsOwner, contract2AsOwner, contractSwapAsOwner, contractAsRebaser;
    beforeEach(async () => {

        [owner, user1, rebaser, autoLiquidityReceiver, TreasuryReceiver, RiskFreeValueReceiver,dex, ...others] = await ethers.getSigners();

        const Titano = await ethers.getContractFactory("Titano_mock");
        titano = await Titano.deploy(dex.address);
        await titano.deployed()

        const Titano2 = await ethers.getContractFactory("Titano2_mock");
        titano2 = await Titano2.deploy(dex.address);
        await titano2.deployed()

        const TitanoSwap = await ethers.getContractFactory("TitanoSwap");
        titanoSwap = await TitanoSwap.deploy();
        await titanoSwap.deployed()

        contract1AsOwner = await titano.connect(owner)
        contract2AsOwner = await titano2.connect(owner)
        contractSwapAsOwner = await titanoSwap.connect(owner)
        contractSwapAsUser1 = await titanoSwap.connect(user1)

        contractAsRebaser = await titano.connect(rebaser);
    });

    it('Should swap', async () => {
        await contract1AsOwner.rebase1(1,100,owner.address,"1447401115466452442794637276423570961504563738454550");
        await contract1AsOwner.transfer(user1.address, 10);
        await contract2AsOwner.setInitialDistributionFinished(true);
        await contract2AsOwner.transfer(titanoSwap.address, 50);

        const balance = await contract2AsOwner.balanceOf(titanoSwap.address);
        console.log("Swap contract balance of Titano v2 - Before", balance)

        await contractSwapAsOwner.setIsSwapStarted(true);
        await contractSwapAsOwner.setTokens(contract1AsOwner.address, contract2AsOwner.address);
        await contractSwapAsUser1.swap(5);

        const balance1 = await contract2AsOwner.balanceOf(user1.address);
        console.log("User balance of Titano v2", balance1)
        const balance3 = await contract2AsOwner.balanceOf(contractSwapAsOwner.address);
        console.log("Swap contract balance of Titano v2 - After", balance3)
    })

});