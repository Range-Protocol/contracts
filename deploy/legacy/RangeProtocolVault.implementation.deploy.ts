import { ethers } from "hardhat";
async function main() {
    let RangeProtocolVault = await ethers.getContractFactory(
        "RangeProtocolVault"
    );
    const vaultImpl = await RangeProtocolVault.deploy();
    console.log(vaultImpl.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
