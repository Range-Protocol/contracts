import { ethers } from "hardhat";
async function main() {
  const ALGEBRA_FACTORY = "0xC848bc597903B4200b9427a3d7F61e3FF0553913";
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
