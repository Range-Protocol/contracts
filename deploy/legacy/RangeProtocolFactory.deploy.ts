import { ethers } from "hardhat";
async function main() {
  const ALGEBRA_FACTORY = "0x411b0fAcC3489691f28ad58c47006AF5E3Ab3A28";
  let RangeProtocolFactory = await ethers.getContractFactory(
    "RangeProtocolFactory"
  );
  const factory = await RangeProtocolFactory.deploy(ALGEBRA_FACTORY);
  console.log("Factory: ", factory.address);
}
// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
