import { ethers } from "hardhat";
async function main() {
  const RangeProtocolVault = await ethers.getContractFactory(
    "RangeProtocolVault",
    {
      libraries: {
        NativeTokenSupport: "0x8731d45ff9684d380302573cCFafd994Dfa7f7d3",
      },
    }
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
