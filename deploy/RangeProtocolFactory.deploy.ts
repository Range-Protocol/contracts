import { ethers } from "hardhat";
import { LedgerSigner } from "@anders-t/ethers-ledger";
async function main() {
  const provider = ethers.getDefaultProvider("");
  const ledger = await new LedgerSigner(provider, "");
  const UNI_V3_FACTORY = "0x1F98431c8aD98523631AE4a59f267346ea31F984";
  let RangeProtocolFactory = await ethers.getContractFactory(
    "RangeProtocolFactory"
  );
  RangeProtocolFactory = await RangeProtocolFactory.connect(ledger);
  const factory = await RangeProtocolFactory.deploy(UNI_V3_FACTORY);
  console.log("Factory: ", factory.address);
}
// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
