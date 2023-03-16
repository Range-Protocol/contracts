import {ethers} from "hardhat";
import {getInitializeData} from "../test/common";

async function main() {
    const [manager] = await ethers.getSigners();
    // console.log((await ethers.provider.getBalance(manager.address)).toString())
    const UNI_V3_FACTORY = "0x1F98431c8aD98523631AE4a59f267346ea31F984";
    const token0 = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
    const token1 = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
    const fee = 10000;
    const treasuryAddress = manager.address;
    const managerAddress = manager.address;
    const managerFee = 500;
    const lowerTick = -50000;
    const upperTick = -40000;
    const name = "Test Token";
    const symbol = "TT";

    const RangeProtocolFactory = await ethers.getContractFactory(
        "RangeProtocolFactory"
    );
    const factory = await RangeProtocolFactory.deploy(UNI_V3_FACTORY);
    console.log("Factory: ", factory.address);

    const RangeProtocolVault = await ethers.getContractFactory(
        "RangeProtocolVault"
    );

    const vaultImpl = await RangeProtocolVault.deploy();
    const data = getInitializeData({
        treasuryAddress,
        managerAddress,
        managerFee,
        name,
        symbol,
    });

    const tx = await factory
        .createVault(
            token0,
            token1,
            fee,
            vaultImpl.address,
            data
        );
    const txReceipt = await tx.wait();
    const [
        {
            args: {vault},
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
