import { ethers } from "hardhat";
import { LedgerSigner } from "@anders-t/ethers-ledger";
import {RangeProtocolFactory} from "../typechain";
async function main() {
    const VAULT = "0x510982F346cF8083FE935080cD61a78E2E7E8fd1";
    const IMPLEMENTATION = "";
    const provider = ethers.getDefaultProvider("");
    const ledger = await new LedgerSigner(provider, "");
    let factory = await ethers.getContractAt(
        "RangeProtocolFactory",
        "0x4bF9CDcCE12924B559928623a5d23598ca19367B"
    ) as RangeProtocolFactory;
    factory = await factory.connect(ledger);

    await factory.upgradeVault(VAULT, IMPLEMENTATION);
}
// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
