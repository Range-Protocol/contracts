import { ethers } from "hardhat";
import fs from "fs";
import path from "path";
import { getInitializeData } from "../../test/common";

const configPath = path.join(__dirname, "../config.json");
async function main() {
    const configData = JSON.parse(fs.readFileSync(configPath));
    const factory = await ethers.getContractAt(
        "RangeProtocolFactory",
        configData.rangeFactory
    );
    const data = getInitializeData({
        managerAddress: configData.manager,
        name: configData.name,
        symbol: configData.symbol,
    });

    const tx = await factory.createVault(
        configData.token0,
        configData.token1,
        configData.fee,
        configData.implementation,
        data
    );
    const txReceipt = await tx.wait();
    const [
        {
            args: { vault },
        },
    ] = txReceipt.events.filter(
        (event: { event: any }) => event.event === "VaultCreated"
    );
    console.log("Vault: ", vault);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
