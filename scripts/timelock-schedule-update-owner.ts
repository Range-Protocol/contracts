import { ethers } from "hardhat";

async function main() {
    const newOwner = ""; // to be updated
    const factoryAddress = ""; // to be updated

    const transferOwnershipInterface = new ethers.utils.Interface([
        "function transferOwnership(address) external",
    ]);
    const updateOwnerdata = transferOwnershipInterface.encodeFunctionData(
        "transferOwnership",
        [newOwner]
    );

   const timeLockInterface = new ethers.utils.Interface([
       "function schedule(address,uint256,bytes,bytes32,bytes32,uint256) external",
   ]);
   const data = timeLockInterface.encodeFunctionData("schedule", [
       factoryAddress,
       0,
       updateOwnerdata,
       ethers.utils.zeroPad("0x", 32),
       ethers.utils.zeroPad("0x", 32),
       300
   ]);

   console.log("data: ", data);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});