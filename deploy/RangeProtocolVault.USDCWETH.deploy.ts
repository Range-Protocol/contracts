import { ethers } from "hardhat";
import { LedgerSigner } from "@anders-t/ethers-ledger";
import { getInitializeData } from "../test/common";

async function main() {
  const provider = ethers.getDefaultProvider(""); // To be updated.
  const ledger = await new LedgerSigner(provider, ""); // To be updated.
  const manager = ""; // To be updated.
  const treasuryAddress = ""; // To be updated.
  const managerAddress = "0x84b43ce5fB1FAF013181FEA96ffA4af6179e396a"; // To be updated.
  const rangeProtocolFactoryAddress = "0x4bF9CDcCE12924B559928623a5d23598ca19367B"; // To be updated.
  const vaultImplAddress = ""; // to be updated.
  const WETH = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
  const USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
  const fee = 500; // To be updated.
  const managerFee = 0; // To be updated.
  const name = ""; // To be updated.
  const symbol = ""; // To be updated.

  let factory = await ethers.getContractAt(
    "RangeProtocolFactory",
      rangeProtocolFactoryAddress
  );
  factory = await factory.connect(ledger);
  const data = getInitializeData({
    treasuryAddress,
    managerAddress,
    managerFee,
    name,
    symbol,
  });

  const tx = await factory.createVault(
    WETH,
    USDC,
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
