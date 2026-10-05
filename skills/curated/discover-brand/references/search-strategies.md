<!-- Adapted by Galeno from the Brand Voice plugin by Tribe AI (MIT). See ../SKILL.md, section "Source". -->
# Search Strategies by Platform

Platform-specific query patterns and tips for maximizing brand material discovery.

Only the platforms this agent can have connected are covered: Notion, Google Drive, Slack, Granola, Fathom, Fireflies and Gmail. Confluence, Box, SharePoint/OneDrive, Gong and Figma are not available here; if the user's brand materials live on one of them, ask the user to paste or share the documents.

## Notion (Primary Discovery Engine)

Notion search can also return results from the sources the user's workspace has connected to Notion (for example Google Drive, Slack or Jira), making it the most valuable single search endpoint.

### Query Patterns

**Direct brand searches:**
- "brand guidelines"
- "style guide"
- "brand voice"
- "tone of voice"
- "messaging framework"

**Sales and marketing content:**
- "pitch deck"
- "sales playbook"
- "email templates"
- "value proposition"
- "competitive positioning"

**Operational brand content:**
- "brand update"
- "rebrand"
- "launch messaging"
- "press release template"
- "social media guidelines"

### Tips
- Notion search may return results from connected sources — one search can cover multiple platforms
- Search for the company name + "brand" to find company-specific guidelines
- Check for databases titled "Brand Assets", "Marketing Resources", or "Content Library"
- Look for pages tagged with "brand", "marketing", "style"

## Google Drive

Google Drive stores shared brand documents, marketing materials, and official style guides.

### Query Patterns

**Folder search:**
- "Brand Guidelines"
- "Marketing"
- "Brand Assets"
- "Style Guide"

**Document search:**
- "brand guide" (PDFs, Google Docs, Google Slides)
- "style guide"
- "messaging framework"
- "brand standards"
- "brand voice"

### Tips
- Check shared drives — brand materials often live in team-wide shared drives
- Look for recently modified brand documents to find the latest version
- Search by owner (marketing team members) to surface brand-owned content
- Google Docs and Slides are common formats for living brand documents
- Check for Google Slides presentations with brand overview decks

## Slack

Slack channels contain informal brand discussions, decisions, and evolving brand voice patterns.

### Query Patterns

**Channel search:**
- Look for channels: #brand, #marketing, #brand-voice, #style-guide, #creative
- Check channel topics and descriptions for brand-related content

**Message search:**
- "brand guidelines"
- "brand voice"
- "tone of voice"
- "style guide"
- "brand update"

**Pinned messages:**
- Check pinned messages in #brand and #marketing channels
- Pinned items often contain approved brand resources or decisions

### Tips
- Search #brand and #marketing channels first — most likely to contain brand discussions
- Look for pinned messages — teams often pin brand guidelines and decisions
- Find brand discussion threads for context on brand evolution
- Slack is a conversational source — ranks as CONVERSATIONAL tier in source triage
- Recent messages may reveal brand changes not yet documented formally

## Fathom and Fireflies (Call and Meeting Transcripts)

Sales call transcripts reveal how the brand actually communicates in practice.

### Query Patterns

**Call search:**
- Search for customer-facing calls: "demo", "discovery", "closing"
- If the user can tell which calls went well (a won deal, a renewed customer), start with those (successful brand application)

**Transcript search:**
- Search transcripts for company-specific value propositions
- Look for recurring phrases across successful calls
- Find calls where competitors are discussed (reveals positioning)

### Tips
- Focus on successful calls — they represent brand voice that works. Which calls were successful comes from the user or from the recording's own data, never from a guess
- Look for consistent opening lines and closing patterns
- Note objection handling language — reveals brand positioning under pressure

## Granola (Meeting Intelligence)

Meeting notes and transcripts from the AI notepad for meetings.

### Query Patterns

**Meeting search:**
- Query for meetings related to: "brand", "positioning", "messaging"
- List recent meetings and filter for customer-facing calls
- Search for strategy sessions and brand planning meetings

**Transcript retrieval:**
- Get full transcripts from high-signal meetings
- Look for recurring themes in meeting notes
- Find meetings with key stakeholders (marketing leads, executives)

### Tips
- Granola captures both meeting notes and transcripts — both are valuable
- Meeting notes often contain summarized brand decisions and action items
- Look for recurring meeting series (weekly brand syncs, marketing standups)
- Cross-reference Granola meeting notes with Fathom or Fireflies call transcripts when both are available

## Gmail (Only When the User Includes It)

A mailbox is personal. Search it only if the user included Gmail in the scope.

### Query Patterns

**Message search:**
- "brand guidelines", "style guide", "brand book" (agencies and designers often deliver them as attachments)
- "email template", "newsletter"
- Outreach and announcements the company actually sent

### Tips
- Email templates and sent outreach rank as OPERATIONAL; one-to-one threads rank as CONVERSATIONAL
- Keep to messages about the brand or sent on behalf of the company; skip everything personal
- Redact recipients' names and contact information from every excerpt

## Cross-Platform Search Tips

### Maximizing Coverage
1. Start with Notion search (broadest coverage when the workspace has connected sources)
2. Check Google Drive for official brand documents
3. Search Slack for brand discussions and decisions
4. Search Fathom and Fireflies for conversational brand patterns
5. Search Granola for meeting transcripts and notes
6. Search Gmail for templates and delivered brand documents, only if the user included it

### Avoiding Duplicates
- Track source URLs to detect the same document across platforms
- When the same content appears on multiple platforms, prefer the most recently updated version
- Note when Notion search returns results from other platforms to avoid double-searching

### Recency Focus
- Focus on content from the last 12 months for operational, conversational, and contextual sources
- Only search further back when looking for explicit brand documents (style guides, brand books)
- When results include older content, prefer the most recently updated version
- Flag any non-AUTHORITATIVE source older than 12 months — it may reflect outdated positioning

### Handling No Results
- If a platform returns zero results, try broader queries ("marketing", "sales")
- Check if the platform is actually connected and authenticated
- Note the gap in the discovery report — the absence of content on a platform is itself useful information
