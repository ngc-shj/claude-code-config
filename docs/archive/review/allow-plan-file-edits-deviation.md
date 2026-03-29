# Coding Deviation Log: allow-plan-file-edits
Created: 2026-03-28

## Deviations from Plan

### D1: Write permission moved from allow to ask
- **Plan description:** Add Read, Edit, Write all to `permissions.allow`
- **Actual implementation:** Read and Edit in `allow`, Write in `ask`
- **Reason:** Security review (S1) identified that unrestricted Write access enables confirmation-free plan file creation/overwrite, creating a prompt injection risk
- **Impact scope:** New plan file creation will require user confirmation; existing file edits remain prompt-free
