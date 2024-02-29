import { ethers } from "hardhat";

async function main() {
  // 0x780BaAf9E91aFaDA141004ed4515f85d65a36101
  const LOGIC_LIB_ADDRESS = "0xccaa7929eAF4b44263f609D1a32FD9BEb3cDf00d";
  const RangeProtocolVault = await ethers.getContractFactory(
    "RangeProtocolVault",
    {
      libraries: {
        LogicLib: LOGIC_LIB_ADDRESS,
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
