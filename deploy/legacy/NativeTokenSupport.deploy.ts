import { ethers } from "hardhat";

async function main() {
    const NativeTokenSupport = await ethers.getContractFactory("NativeTokenSupport");
    const nativeTokenSupport = await NativeTokenSupport.deploy();
    console.log("Native Token Support: ", nativeTokenSupport.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
