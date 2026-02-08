import {
  KhaaliSplitFriends,
  KhaaliSplitGroups,
  KhaaliSplitExpenses,
  KhaaliSplitSettlement,
  KhaaliSplitSubnames,
  KhaaliSplitReputation,
  KhaaliSplitResolver,
  KdioDeployer,
} from "generated";

// ── Helpers ──────────────────────────────────────────

const addr = (a: string): string => a.toLowerCase();

/** Sorted pair ID so alice-bob == bob-alice */
const friendPairId = (a: string, b: string): string => {
  const la = addr(a);
  const lb = addr(b);
  return la < lb ? `${la}-${lb}` : `${lb}-${la}`;
};

// ── Friends (4 handlers) ─────────────────────────────

KhaaliSplitFriends.PubKeyRegistered.handler(async ({ event, context }) => {
  context.RegisteredUser.set({
    id: addr(event.params.user),
    pubKey: event.params.pubKey,
    registeredAt: event.block.timestamp,
    txHash: event.transaction.hash,
  });
});

KhaaliSplitFriends.FriendRequested.handler(async ({ event, context }) => {
  context.FriendRequest.set({
    id: friendPairId(event.params.from, event.params.to),
    from: addr(event.params.from),
    to: addr(event.params.to),
    status: "pending",
    requestedAt: event.block.timestamp,
    acceptedAt: undefined,
    removedAt: undefined,
    txHash: event.transaction.hash,
  });
});

KhaaliSplitFriends.FriendAccepted.handler(async ({ event, context }) => {
  const id = friendPairId(event.params.user, event.params.friend);
  const existing = await context.FriendRequest.get(id);
  context.FriendRequest.set({
    id,
    from: existing?.from ?? addr(event.params.user),
    to: existing?.to ?? addr(event.params.friend),
    status: "accepted",
    requestedAt: existing?.requestedAt ?? event.block.timestamp,
    acceptedAt: event.block.timestamp,
    removedAt: undefined,
    txHash: event.transaction.hash,
  });
});

KhaaliSplitFriends.FriendRemoved.handler(async ({ event, context }) => {
  const id = friendPairId(event.params.user, event.params.friend);
  const existing = await context.FriendRequest.get(id);
  context.FriendRequest.set({
    id,
    from: existing?.from ?? addr(event.params.user),
    to: existing?.to ?? addr(event.params.friend),
    status: "removed",
    requestedAt: existing?.requestedAt ?? event.block.timestamp,
    acceptedAt: existing?.acceptedAt,
    removedAt: event.block.timestamp,
    txHash: event.transaction.hash,
  });
});

// ── Groups (4 handlers) ──────────────────────────────

KhaaliSplitGroups.GroupCreated.handler(async ({ event, context }) => {
  const groupId = event.params.groupId.toString();
  const creator = addr(event.params.creator);

  context.Group.set({
    id: groupId,
    nameHash: event.params.nameHash,
    creator,
    memberCount: 1,
    createdAt: event.block.timestamp,
    txHash: event.transaction.hash,
  });

  // Creator is automatically an accepted member
  context.GroupMember.set({
    id: `${groupId}-${creator}`,
    group_id: groupId,
    memberAddress: creator,
    invitedBy: creator,
    status: "accepted",
    invitedAt: event.block.timestamp,
    acceptedAt: event.block.timestamp,
    leftAt: undefined,
    txHash: event.transaction.hash,
  });
});

KhaaliSplitGroups.MemberInvited.handler(async ({ event, context }) => {
  const groupId = event.params.groupId.toString();
  context.GroupMember.set({
    id: `${groupId}-${addr(event.params.invitee)}`,
    group_id: groupId,
    memberAddress: addr(event.params.invitee),
    invitedBy: addr(event.params.inviter),
    status: "invited",
    invitedAt: event.block.timestamp,
    acceptedAt: undefined,
    leftAt: undefined,
    txHash: event.transaction.hash,
  });
});

KhaaliSplitGroups.MemberAccepted.handler(async ({ event, context }) => {
  const groupId = event.params.groupId.toString();
  const memberId = `${groupId}-${addr(event.params.member)}`;

  const existing = await context.GroupMember.get(memberId);
  context.GroupMember.set({
    id: memberId,
    group_id: groupId,
    memberAddress: addr(event.params.member),
    invitedBy: existing?.invitedBy ?? addr(event.params.member),
    status: "accepted",
    invitedAt: existing?.invitedAt ?? event.block.timestamp,
    acceptedAt: event.block.timestamp,
    leftAt: undefined,
    txHash: event.transaction.hash,
  });

  const group = await context.Group.get(groupId);
  if (group) {
    context.Group.set({
      ...group,
      memberCount: group.memberCount + 1,
      txHash: event.transaction.hash,
    });
  }
});

KhaaliSplitGroups.MemberLeft.handler(async ({ event, context }) => {
  const groupId = event.params.groupId.toString();
  const memberId = `${groupId}-${addr(event.params.member)}`;

  const existing = await context.GroupMember.get(memberId);
  context.GroupMember.set({
    id: memberId,
    group_id: groupId,
    memberAddress: addr(event.params.member),
    invitedBy: existing?.invitedBy ?? addr(event.params.member),
    status: "left",
    invitedAt: existing?.invitedAt ?? event.block.timestamp,
    acceptedAt: existing?.acceptedAt,
    leftAt: event.block.timestamp,
    txHash: event.transaction.hash,
  });

  const group = await context.Group.get(groupId);
  if (group) {
    context.Group.set({
      ...group,
      memberCount: Math.max(0, group.memberCount - 1),
      txHash: event.transaction.hash,
    });
  }
});

// ── Expenses (2 handlers) ────────────────────────────

KhaaliSplitExpenses.ExpenseAdded.handler(async ({ event, context }) => {
  context.Expense.set({
    id: event.params.expenseId.toString(),
    group_id: event.params.groupId.toString(),
    creator: addr(event.params.creator),
    dataHash: event.params.dataHash,
    encryptedData: event.params.encryptedData,
    createdAt: event.block.timestamp,
    createdTxHash: event.transaction.hash,
    updatedAt: undefined,
    updatedTxHash: undefined,
  });
});

KhaaliSplitExpenses.ExpenseUpdated.handler(async ({ event, context }) => {
  const id = event.params.expenseId.toString();
  const existing = await context.Expense.get(id);
  context.Expense.set({
    id,
    group_id: existing?.group_id ?? event.params.groupId.toString(),
    creator: existing?.creator ?? addr(event.params.creator),
    dataHash: event.params.dataHash,
    encryptedData: event.params.encryptedData,
    createdAt: existing?.createdAt ?? event.block.timestamp,
    createdTxHash: existing?.createdTxHash ?? event.transaction.hash,
    updatedAt: event.block.timestamp,
    updatedTxHash: event.transaction.hash,
  });
});

// ── Settlement (9 handlers) ──────────────────────────

KhaaliSplitSettlement.SettlementCompleted.handler(async ({ event, context }) => {
  const chainId = event.chainId;
  context.Settlement.set({
    id: `${chainId}-${event.transaction.hash}-${event.logIndex}`,
    sender: addr(event.params.sender),
    recipient: addr(event.params.recipient),
    token: addr(event.params.token),
    amount: event.params.amount,
    senderReputation: event.params.senderReputation,
    memo: event.params.memo,
    sourceChainId: chainId,
    blockNumber: event.block.number,
    blockTimestamp: event.block.timestamp,
    txHash: event.transaction.hash,
  });
});

KhaaliSplitSettlement.TokenAdded.handler(async ({ event, context }) => {
  const chainId = event.chainId;
  context.AllowedToken.set({
    id: `${chainId}-${addr(event.params.token)}`,
    chainId,
    token: addr(event.params.token),
    isAllowed: true,
    txHash: event.transaction.hash,
  });
});

KhaaliSplitSettlement.TokenRemoved.handler(async ({ event, context }) => {
  const chainId = event.chainId;
  const id = `${chainId}-${addr(event.params.token)}`;
  const existing = await context.AllowedToken.get(id);
  context.AllowedToken.set({
    id,
    chainId,
    token: existing?.token ?? addr(event.params.token),
    isAllowed: false,
    txHash: event.transaction.hash,
  });
});

KhaaliSplitSettlement.TokenMessengerUpdated.handler(async ({ event, context }) => {
  const chainId = event.chainId;
  context.SettlementConfig.set({
    id: `${chainId}-tokenMessenger`,
    chainId,
    configType: "tokenMessenger",
    value: addr(event.params.newTokenMessenger),
    txHash: event.transaction.hash,
  });
});

KhaaliSplitSettlement.GatewayWalletUpdated.handler(async ({ event, context }) => {
  const chainId = event.chainId;
  context.SettlementConfig.set({
    id: `${chainId}-gatewayWallet`,
    chainId,
    configType: "gatewayWallet",
    value: addr(event.params.newGatewayWallet),
    txHash: event.transaction.hash,
  });
});

KhaaliSplitSettlement.GatewayMinterUpdated.handler(async ({ event, context }) => {
  const chainId = event.chainId;
  context.SettlementConfig.set({
    id: `${chainId}-gatewayMinter`,
    chainId,
    configType: "gatewayMinter",
    value: addr(event.params.newGatewayMinter),
    txHash: event.transaction.hash,
  });
});

KhaaliSplitSettlement.DomainConfigured.handler(async ({ event, context }) => {
  const sourceChainId = event.chainId;
  const targetChainId = Number(event.params.chainId);
  context.CctpDomain.set({
    id: `${sourceChainId}-${targetChainId}`,
    sourceChainId,
    targetChainId,
    domain: Number(event.params.domain),
    txHash: event.transaction.hash,
  });
});

KhaaliSplitSettlement.SubnameRegistryUpdated.handler(async ({ event, context }) => {
  const chainId = event.chainId;
  context.SettlementConfig.set({
    id: `${chainId}-subnameRegistry`,
    chainId,
    configType: "subnameRegistry",
    value: addr(event.params.newSubnameRegistry),
    txHash: event.transaction.hash,
  });
});

KhaaliSplitSettlement.ReputationContractUpdated.handler(async ({ event, context }) => {
  const chainId = event.chainId;
  context.SettlementConfig.set({
    id: `${chainId}-reputationContract`,
    chainId,
    configType: "reputationContract",
    value: addr(event.params.newReputationContract),
    txHash: event.transaction.hash,
  });
});

// ── Subnames (5 handlers) ────────────────────────────

KhaaliSplitSubnames.SubnameRegistered.handler(async ({ event, context }) => {
  context.Subname.set({
    id: event.params.node,
    label: event.params.label,
    owner: addr(event.params.owner),
    registeredAt: event.block.timestamp,
    txHash: event.transaction.hash,
  });
});

KhaaliSplitSubnames.TextRecordSet.handler(async ({ event, context }) => {
  const node = event.params.node;
  context.TextRecord.set({
    id: `${node}-${event.params.key}`,
    subname_id: node,
    key: event.params.key,
    value: event.params.value,
    txHash: event.transaction.hash,
  });
});

KhaaliSplitSubnames.AddrRecordSet.handler(async ({ event, context }) => {
  context.AddrRecord.set({
    id: event.params.node,
    node: event.params.node,
    addr: addr(event.params.addr),
    txHash: event.transaction.hash,
  });
});

// Admin events — no entity, just log
KhaaliSplitSubnames.BackendUpdated.handler(async ({ event, context }) => {
  context.log.info(`Subnames BackendUpdated: ${event.params.newBackend}`);
});

KhaaliSplitSubnames.ReputationContractUpdated.handler(async ({ event, context }) => {
  context.log.info(`Subnames ReputationContractUpdated: ${event.params.newReputationContract}`);
});

// ── Reputation (5 handlers) ──────────────────────────

KhaaliSplitReputation.ReputationUpdated.handler(async ({ event, context }) => {
  const id = addr(event.params.user);
  const existing = await context.ReputationScore.get(id);
  context.ReputationScore.set({
    id,
    score: event.params.newScore,
    totalSettlements: (existing?.totalSettlements ?? 0) + 1,
    successfulSettlements:
      (existing?.successfulSettlements ?? 0) + (event.params.wasSuccess ? 1 : 0),
    failedSettlements:
      (existing?.failedSettlements ?? 0) + (event.params.wasSuccess ? 0 : 1),
    lastUpdatedAt: event.block.timestamp,
    txHash: event.transaction.hash,
  });
});

KhaaliSplitReputation.UserNodeSet.handler(async ({ event, context }) => {
  context.ReputationUserNode.set({
    id: addr(event.params.user),
    node: event.params.node,
    txHash: event.transaction.hash,
  });
});

// Admin events — no entity, just log
KhaaliSplitReputation.BackendUpdated.handler(async ({ event, context }) => {
  context.log.info(`Reputation BackendUpdated: ${event.params.newBackend}`);
});

KhaaliSplitReputation.SubnameRegistryUpdated.handler(async ({ event, context }) => {
  context.log.info(`Reputation SubnameRegistryUpdated: ${event.params.newSubnameRegistry}`);
});

KhaaliSplitReputation.SettlementContractUpdated.handler(async ({ event, context }) => {
  context.log.info(`Reputation SettlementContractUpdated: ${event.params.newSettlementContract}`);
});

// ── Resolver (3 handlers) ────────────────────────────

KhaaliSplitResolver.SignerAdded.handler(async ({ event, context }) => {
  context.ResolverSigner.set({
    id: addr(event.params.signer),
    isActive: true,
    txHash: event.transaction.hash,
  });
});

KhaaliSplitResolver.SignerRemoved.handler(async ({ event, context }) => {
  context.ResolverSigner.set({
    id: addr(event.params.signer),
    isActive: false,
    txHash: event.transaction.hash,
  });
});

KhaaliSplitResolver.UrlUpdated.handler(async ({ event, context }) => {
  context.ResolverUrl.set({
    id: "current",
    url: event.params.newUrl,
    txHash: event.transaction.hash,
  });
});

// ── kdioDeployer (1 handler) ─────────────────────────

KdioDeployer.Deployed.handler(async ({ event, context }) => {
  context.Deployment.set({
    id: `${event.params.salt}-${addr(event.params.proxy)}`,
    proxy: addr(event.params.proxy),
    salt: event.params.salt,
    implementation: addr(event.params.implementation),
    chainId: event.chainId,
    blockNumber: event.block.number,
    blockTimestamp: event.block.timestamp,
    txHash: event.transaction.hash,
  });
});
