export interface RuleField {
  name: string;
  from?: string;
  selector?: string;
  attribute?: string;
  required?: boolean;
  defaultValue?: string;
  transforms?: string[];
}
export interface RuleQuery { name: string; value: string; }
export interface RuleOperation {
  name: string;
  path: string;
  query?: RuleQuery[];
  headers?: RuleQuery[];
  root?: string;
  items?: string;
  requiredMarker?: string;
  emptyMarker?: string;
  fields: RuleField[];
  nextPath?: string;
  nextSelector?: string;
}
// Execution representation. External JSON is converted only by RuleValidator.
export interface RuleDefinition {
  id: string;
  version: number;
  format: string;
  operations: RuleOperation[];
  imageHeaders?: RuleQuery[];
}

export interface ValidatedRulePackage {
  id: string; name: string; sourceVersion: number; ruleFormatVersion: number;
  engineMin: number; engineMax: number; baseUrl: string; allowedHosts: string[];
  capabilities: string[]; definition: RuleDefinition;
}
