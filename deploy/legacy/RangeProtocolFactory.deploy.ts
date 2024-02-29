import { ethers } from "hardhat";
async function main() {
  const ALGEBRA_FACTORY = "0x1a3c9B1d2F0529D97f2afC5136Cc23e58f1FD35B";
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
