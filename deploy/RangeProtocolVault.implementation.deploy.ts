import { ethers } from "hardhat";
import { LedgerSigner } from "@anders-t/ethers-ledger";
import { getInitializeData } from "../test/common";

async function main() {
    const provider = ethers.getDefaultProvider(""); // To be updated.
    const ledger = await new LedgerSigner(provider, ""); // To be updated.
    let RangeProtocolVault = await ethers.getContractFactory(
        "RangeProtocolVault"
    );
    RangeProtocolVault = await RangeProtocolVault.connect(ledger);
    const vaultImpl = await RangeProtocolVault.deploy();
    console.log(vaultImpl.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
