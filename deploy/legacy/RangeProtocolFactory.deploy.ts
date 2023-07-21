import { ethers } from "hardhat";
async function main() {
  const UNI_V3_FACTORY = "0x1F98431c8aD98523631AE4a59f267346ea31F984";
  let RangeProtocolFactory = await ethers.getContractFactory(
    "RangeProtocolFactory"
  );
  const factory = await RangeProtocolFactory.deploy(UNI_V3_FACTORY);
  console.log("Factory: ", factory.address);
}
// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
