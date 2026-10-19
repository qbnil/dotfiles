# ste100-skill

A skill for writing technical documentation in Simplified Technical English (ADS-STE100). Works with OpenCode, Claude, ChatGPT, and any AI agent that supports custom instructions or skills.

## What it does

STE100 is a controlled language specification from the Aerospace and Deflang Association. It restricts English to a simplified vocabulary and grammar rules so technical documentation is clear and unambiguous.

This skill teaches an AI agent to write STE-compliant documentation: maintenance manuals, SOPs, technical guides, and any procedure where ambiguity can cause failure.

## What it checks

- Sentence length (max 20 words)
- Active voice only
- One verb per sentence
- Approved vocabulary
- Procedure formatting
- Warning placement
- Article usage
- Abbreviation definitions

## Install

### OpenCode

Copy the `ste100` folder to one of these locations:

```
~/.agents/skills/ste100/
~/.config/opencode/skills/ste100/
.opencode/skills/ste100/
```

Or clone directly:

```bash
git clone https://github.com/sdsheeks/ste100-skill.git ~/.agents/skills/ste100
```

Restart OpenCode after installing. The skill loads automatically when you ask for technical documentation.

### Claude (claude.ai or Claude Desktop)

1. Start a new conversation
2. Click the **+** icon in the message bar
3. Select **Add from files** or drag the files in
4. Upload these files from the skill:
   - `SKILL.md`
   - `references/approved-words.md`
   - `references/procedure-format.md`
   - `references/examples.md`
5. Start your prompt with: "Follow the STE100 skill instructions to write..."

Claude uses uploaded files as project knowledge. The files stay in the conversation until you remove them.

### Claude Code

Copy the skill to the Claude skills directory:

```bash
git clone https://github.com/sdsheeks/ste100-skill.git ~/.claude/skills/ste100
```

Restart Claude Code. The skill loads automatically when relevant.

### ChatGPT

**Option 1: Custom Instructions**

1. Go to **Settings > Personalization > Custom Instructions**
2. Paste this into the "What would you like ChatGPT to know?" box:

```
When I ask you to write technical documentation, follow these STE rules:
- Maximum 20 words per sentence
- Active voice only, no passive constructions
- One verb per sentence
- Use approved STE vocabulary (use instead of utilize, start instead of commence, etc.)
- One instruction per step in procedures
- Every noun needs an article (the, a, an)
- Define abbreviations on first use
- Spell out numbers 1-10, use digits for 11+
- Place warnings before the step they apply to
- Use vertical lists, not inline lists

Approved word substitutions:
- utilize → use
- commence → start
- terminate → stop
- facilitate → help
- ascertain → find
- prior to → before
- subsequent to → after
- component → part
- demonstrate → show
- eliminate → remove
- adjacent → next to
- approximately → about
- modification → change
```

3. Click **Save**

**Option 2: Upload Files**

1. Start a new conversation
2. Click the **+** icon and select **Upload from computer**
3. Upload `SKILL.md`, `references/approved-words.md`, `references/procedure-format.md`, and `references/examples.md`
4. Ask ChatGPT to write technical documentation

**Option 3: Project Knowledge (Plus/Team/Enterprise)**

1. Go to **Projects** in the sidebar
2. Create a new project or open an existing one
3. Click **Add files** under Project Knowledge
4. Upload the skill files
5. Start a conversation in that project. ChatGPT references the uploaded files automatically.

### Cursor / Windsurf / Other AI Code Editors

Copy the skill files into your project:

```bash
git clone https://github.com/sdsheeks/ste100-skill.git .cursor/skills/ste100
```

Or add the rules to your project's `.cursorrules` file by copying the contents of `SKILL.md`.

## Usage

**OpenCode:**

```
@ste100 write a procedure for replacing the fuel filter
```

**Claude:**

```
Follow the STE100 skill instructions to write a procedure for replacing the fuel filter.
```

**ChatGPT:**

```
Write a maintenance procedure for replacing the fuel filter. Use the STE rules from my custom instructions.
```

## References

- `references/approved-words.md` — STE approved vocabulary with meanings
- `references/procedure-format.md` — procedure template and formatting rules
- `references/examples.md` — before/after transformations

## License

MIT
