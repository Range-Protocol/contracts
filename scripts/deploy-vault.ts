import { ethers } from "hardhat";
import { LedgerSigner } from "@anders-t/ethers-ledger";
import {RangeProtocolFactory} from "../typechain";
import {getInitializeData} from "../test/common";
async function main() {
    const managerAddress = ""; // to be updated.
    const token0 = ""; // to be updated.
    const token1 = ""; // to be updated.
    const fee = 100;
    const name = ""; // To be updated.
    const symbol = ""; // To be updated.
    const vaultImplAddress = "";
    const data = getInitializeData({
        managerAddress,
        name,
        symbol,
    });
    const createVaultInterface = new ethers.utils.Interface([
        "function createVault(address tokenA, address tokenB, uint24 fee, address implementation, bytes memory data)"
    ]);
    const txData = createVaultInterface.encodeFunctionData("createVault", [
        token0,
        token1,
        fee,
        vaultImplAddress,
        data
    ]);
    console.log(txData);
}
// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
