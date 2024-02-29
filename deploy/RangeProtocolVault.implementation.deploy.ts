import { ethers } from "hardhat";

async function main() {
  const LOGIC_LIB_ADDRESS = "0x420277F9681e31e06DAD061c560f43303360E6dA";
  let RangeProtocolVault = await ethers.getContractFactory(
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
