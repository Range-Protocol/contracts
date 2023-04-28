import { ethers } from "hardhat";
import { getInitializeData } from "../../test/common";

async function main() {
  const managerAddress = "0x84b43ce5fB1FAF013181FEA96ffA4af6179e396a"; // To be updated.
  const rangeProtocolFactoryAddress =
    "0x5427d4E232b2520550889c19799cA4adF59076bA"; // To be updated.
  const vaultImplAddress = "0xc4e502EFB8Bdf50dBb36b30E73800bA5Fc71cCF0"; // to be updated.
  const token0 = "0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270";
  const token1 = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174";
  const name = "Test Token"; // To be updated.
  const symbol = "TT"; // To be updated.

  let factory = await ethers.getContractAt(
    "RangeProtocolFactory",
    rangeProtocolFactoryAddress
  );
  const data = getInitializeData({
    managerAddress,
    name,
    symbol,
  });

  const tx = await factory.createVault(token0, token1, vaultImplAddress, data);
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
