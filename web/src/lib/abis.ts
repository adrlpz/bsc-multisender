// ABI for Multisender v1.1
// Generated from contracts/src/Multisender.sol after audit fixes (M1/M2/M3 + L4)
export const multisenderAbi = [
  // ----- Read -----
  {
    type: "function",
    name: "feeBps",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint16" }],
  },
  {
    type: "function",
    name: "feeReceiver",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "address" }],
  },
  {
    type: "function",
    name: "MAX_RECIPIENTS_FREE",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
  {
    type: "function",
    name: "MAX_RECIPIENTS_STANDARD",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
  {
    type: "function",
    name: "MAX_FEE_BPS",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint16" }],
  },
  {
    type: "function",
    name: "owner",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "address" }],
  },
  // ----- Write: send -----
  {
    type: "function",
    name: "multisendBNB",
    stateMutability: "payable",
    inputs: [
      { name: "recipients", type: "address[]" },
      { name: "amounts", type: "uint256[]" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "multisendToken",
    stateMutability: "nonpayable",
    inputs: [
      { name: "token", type: "address" },
      { name: "recipients", type: "address[]" },
      { name: "amounts", type: "uint256[]" },
      { name: "maxFeeBps", type: "uint16" },
    ],
    outputs: [],
  },
  // ----- Events -----
  {
    type: "event",
    name: "MultisendBNB",
    inputs: [
      { indexed: true, name: "sender", type: "address" },
      { indexed: false, name: "totalAmount", type: "uint256" },
      { indexed: false, name: "recipientCount", type: "uint256" },
    ],
  },
  {
    type: "event",
    name: "MultisendToken",
    inputs: [
      { indexed: true, name: "sender", type: "address" },
      { indexed: true, name: "token", type: "address" },
      { indexed: false, name: "totalAmount", type: "uint256" },
      { indexed: false, name: "recipientCount", type: "uint256" },
      { indexed: false, name: "fee", type: "uint256" },
    ],
  },
  // ----- Errors (custom) -----
  { type: "error", name: "LengthMismatch", inputs: [] },
  { type: "error", name: "NoRecipients", inputs: [] },
  {
    type: "error",
    name: "TooManyRecipients",
    inputs: [
      { name: "provided", type: "uint256" },
      { name: "max", type: "uint256" },
    ],
  },
  { type: "error", name: "ZeroAmount", inputs: [{ name: "index", type: "uint256" }] },
  { type: "error", name: "ZeroAddress", inputs: [{ name: "index", type: "uint256" }] },
  {
    type: "error",
    name: "ValueMismatch",
    inputs: [
      { name: "sent", type: "uint256" },
      { name: "expected", type: "uint256" },
    ],
  },
  {
    type: "error",
    name: "FeeAboveMax",
    inputs: [
      { name: "actual", type: "uint16" },
      { name: "max", type: "uint16" },
    ],
  },
  { type: "error", name: "FeeOnTransferNotSupported", inputs: [] },
  { type: "error", name: "BNBTransferFailed", inputs: [{ name: "recipient", type: "address" }] },
] as const;

export const erc20Abi = [
  {
    type: "function",
    name: "name",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "string" }],
  },
  {
    type: "function",
    name: "symbol",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "string" }],
  },
  {
    type: "function",
    name: "decimals",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint8" }],
  },
  {
    type: "function",
    name: "balanceOf",
    stateMutability: "view",
    inputs: [{ name: "owner", type: "address" }],
    outputs: [{ type: "uint256" }],
  },
  {
    type: "function",
    name: "allowance",
    stateMutability: "view",
    inputs: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
    ],
    outputs: [{ type: "uint256" }],
  },
  {
    type: "function",
    name: "approve",
    stateMutability: "nonpayable",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ type: "bool" }],
  },
] as const;
