import { ethers } from "hardhat";
import fs from "fs";
import path from "path";

const configPath = path.join(__dirname, "../config.json");
async function main() {
  const configData = JSON.parse(fs.readFileSync(configPath));
  const AMM_FACTORY = configData.ammFactory;
  const RangeProtocolFactory = await ethers.getContractFactory(
    "RangeProtocolFactory"
  );
  const factory = await RangeProtocolFactory.deploy(AMM_FACTORY);
  console.log("Factory: ", factory.address);
  configData.rangeFactory = factory.address;
  fs.writeFileSync(configPath, JSON.stringify(configData));
  console.log("DONE!");
}
// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
