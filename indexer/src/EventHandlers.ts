import { USDC } from "generated";

USDC.Transfer.handler(async ({ event, context }) => {
  const chainId = event.chainId;
  const id = `${chainId}-${event.transaction.hash}-${event.logIndex}`;

  context.USDCTransfer.set({
    id,
    from: event.params.from.toLowerCase(),
    to: event.params.to.toLowerCase(),
    value: event.params.value,
    blockNumber: event.block.number,
    blockTimestamp: event.block.timestamp,
    txHash: event.transaction.hash,
  });
});
