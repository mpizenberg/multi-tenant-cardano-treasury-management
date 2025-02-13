The goal of this project is to provide a secure treasury management solution for multi-tenant organizations.
Typically, these are organizations where members are sharing a common treasury, but with multiple scopes, relatively autonomous.

In the optimistic context, the aimed capabilities are the following:

- Anything is possible as long as all scope owners present their credentials
- Each scope has access to a portion of the treasury
- Small withdrawals within a scope only require the scope owner credentials, with a configurable rolling net limit
- Bigger withdrawals require other scope owners credentials, configurable
- All withdrawals must present a rationale

The contracts must also be safe in the following situations, potentially adversarial:

- Some credential is lost or compromised
- Some member is acting against the organization goals
- Some scope needs to be redefined
- Scope owners need to change their credentials

To address these, the contracts may have the following capabilities:

- Any change can be done with M-of-N credentials and a contestation period
- Repeated contestations are overruled by the M-of-N credentials to avoid adversarial deadlocks
