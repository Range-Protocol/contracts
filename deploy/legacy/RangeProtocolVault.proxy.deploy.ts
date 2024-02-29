import { ethers } from "hardhat";
import { getInitializeData } from "../../test/common";

async function main() {
  const managerAddress = "0x84b43ce5fB1FAF013181FEA96ffA4af6179e396a"; // To be updated.
  const rangeProtocolFactoryAddress =
    "0xc4Fe39a1588807CfF8d8897050c39F065eBAb0B8"; // To be updated.
  const vaultImplAddress = "0x969E3128DB078b179E9F3b3679710d2443cCDB72"; // to be updated.
  const token0 = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48";
  const token1 = "0xdac17f958d2ee523a2206206994597c13d831ec7";
  const fee = 100; // To be updated.
  const name = "Test Token"; // To be updated.
  const symbol = "TT"; // To be updated.

  const factory = await ethers.getContractAt(
    "RangeProtocolFactory",
    rangeProtocolFactoryAddress
  );
  const data = getInitializeData({
    managerAddress,
    name,
    symbol,
    WETH9: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
  });

  const tx = await factory.createVault(
    token0,
    token1,
    fee,
    vaultImplAddress,
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
