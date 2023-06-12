import { ethers } from "hardhat";

async function main() {
  const newOwner = ""; // to be updated
  const transferOwnershipInterface = new ethers.utils.Interface([
    "function transferOwnership(address) external",
  ]);
  const data = transferOwnershipInterface.encodeFunctionData(
    "transferOwnership",
    [newOwner]
  );
  console.log("data: ", data);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
