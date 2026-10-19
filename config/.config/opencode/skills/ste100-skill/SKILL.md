---
name: ste100
description: Write technical documentation in Simplified Technical English (ADS-STE100). Use when creating, editing, or reviewing maintenance manuals, technical guides, SOPs, or any aerospace/defense/engineering documentation that requires controlled language.
metadata:
  author: sdsheeks
  license: MIT
  spec: ASD-STE100 Issue 8
---

# STE100 Skill

Write technical documentation that follows Simplified Technical English (STE), the controlled language defined in ASD-STE100.

STE exists because complex equipment requires clear instructions. Ambiguity in a maintenance manual can ground an aircraft. Ambiguity in a procedure can cause injury. STE eliminates ambiguity by restricting vocabulary, grammar, and sentence structure.

## When to Use

Use this skill for:

- Maintenance manuals and service bulletins
- Standard operating procedures (SOPs)
- Technical installation guides
- Airworthiness instructions
- Any documentation where a non-native English speaker must follow steps without misinterpretation

Do not use for marketing copy, blog posts, or internal chat. STE is for documentation where clarity prevents failure.

## Writing Rules

### Grammar Rules

| Rule | Constraint |
|------|-----------|
| Sentences | Maximum 20 words |
| Nouns per sentence | Maximum 6 |
| Verbs per sentence | Maximum 1 (active voice only) |
| Voice | Active only. No passive constructions |
| Tense | Present tense for instructions, past tense for descriptions |
| Articles | Use "the" for specific items, "a/an" for general items. Never omit |
| Pronouns | Avoid where possible. Use the noun instead |
| Abbreviations | Define on first use. Use the abbreviation after |
| Numbers | Spell out 1-10. Use digits for 11+ |
| Hyphenation | Use for compound modifiers before a noun |

### Vocabulary Rules

STE limits vocabulary to approved words. See [references/approved-words.md](references/approved-words.md) for the full list.

Key principles:

1. **One word, one meaning.** "Follow" always means track or trace. "Proceed" means go forward. Never use "follow" to mean "proceed."

2. **Use the approved word.** If a technical term has an approved STE word, use it. If not, use the simplest possible word.

3. **No jargon.** Replace domain-specific synonyms with the approved term.

Common substitutions:

| Do not use | Use instead |
|------------|-------------|
| commence | start |
| utilise / utilize | use |
| in order to | to |
| ascertain | find, make sure |
| facilitate | help, let |
| prior to | before |
| subsequent to | after |
| terminate | stop |
| initiate | start |
| component | part |
| requires | needs, must |
| indicates | shows |
| approximately | about |
| modification | change |
| demonstrate | show |
| eliminate | remove |
| adjacent | next to |

### Structure Rules

1. **One topic per sentence.** If you need "and" to connect two actions, split into two sentences.

2. **One instruction per step.** Each step in a procedure does one thing.

3. **Use vertical lists.** List items vertically, not inline. Each item is a separate line.

4. **Use headings.** Break content into short sections. A section covers one topic.

5. **No hidden instructions.** "Make sure the valve is open" is passive. "Open the valve" is active.

## Procedure Format

Technical procedures follow a strict format. See [references/procedure-format.md](references/procedure-format.md) for the full template.

Minimum structure:

- **Title** — what the procedure accomplishes
- **Conditions** — when to perform it, prerequisites
- **Tools/Parts** — what is needed
- **Steps** — numbered, one action each, imperative mood
- **Expected Results** — what success looks like

## Quick Checks

Before delivering documentation:

- Any sentence over 20 words? Split it.
- Any passive voice? Rewrite in active. "The valve is opened" becomes "Open the valve."
- Any word not on the approved list? Replace it.
- Any sentence with more than one verb? Split it.
- Any noun missing an article? Add "the" or "a/an."
- Any abbreviation not defined on first use? Define it.
- Any procedure step doing two things? Split into two steps.
- Any inline list with 3+ items? Move to vertical format.
- Any technical jargon? Replace with approved word.
- Any "and" connecting two actions? Split into two sentences.

## Scoring

Rate each dimension 1-10:

| Dimension | Question |
|-----------|----------|
| Simplicity | Could a non-native speaker follow this? |
| Clarity | Is each instruction unambiguous? |
| Completeness | Are all steps and parts listed? |
| Consistency | Does every term match the approved word list? |
| Structure | Does each sentence contain one idea? |

Below 40/50: revise before publishing.

## References

- [references/approved-words.md](references/approved-words.md) — STE approved vocabulary with meanings
- [references/procedure-format.md](references/procedure-format.md) — procedure template and formatting rules
- [references/examples.md](references/examples.md) — before/after transformations

## License

MIT
