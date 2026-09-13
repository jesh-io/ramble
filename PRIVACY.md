# Privacy

Ramble defaults to Apple's on-device speech engine and local cleanup. Optional
remote speech engines receive audio and personal vocabulary; remote cleanup
receives transcript text and vocabulary. Incremental cleanup can send text before
recording stops. Provider data retention and billing are controlled by that provider.
Downloaded local models require an initial network download.

## Local data

Audio recording and transcript history are off by default. If enabled, Mac session
audio and transcripts are stored in `~/Library/Application Support/Ramble/recordings`.
Configuration, optional `history.jsonl`, and the local `usage.jsonl` ledger live
in `~/.config/ramble`. Audio and history have independent 72-hour retention defaults;
`0` means forever. Pruning runs at launch and after dictation, not while the app is
closed. Turning saving off does not delete existing files. Storage can delete all
recordings/history; the usage ledger can be removed through Finder.

The usage ledger contains local provider/model names and billing counts, not
transcript text; it is never uploaded by analytics. Configuration includes personal
vocabulary and endpoint settings. Keys entered through Accounts are saved in
Keychain. Inline keys in imported config migrate on save when Keychain is available;
if migration fails, the original file is retained, so do not share it. Corrupt
configuration backups may retain whatever the original contained.

Directories containing private files use owner-only permissions. Temporary audio
is also necessary for batch transcription even when recording retention is off,
and is deleted on completion/cancellation. A process crash can leave temporary
files until OS cleanup. Deleting files does not erase backups or guarantee secure
erasure on storage media. Clipboard and Accessibility output go to the selected
application and may be retained by clipboard managers or that application.

## Product analytics

Product analytics is separately opt-in and off by default. The release only uses
local diagnostic logging and sends no analytics to a server. Events include
allowlisted provider/model categories, numeric length/duration buckets, coarse
local daypart, process-local interval buckets, feature choices and outcomes.
Analytics never receives transcript text, audio, vocabulary, prompts, raw errors,
credentials, custom account/model names, file paths, or a persistent user ID.

The independent analytics package includes an HTTP adapter for a future backend.
Enabling that backend requires updating this disclosure and obtaining consent for
network delivery. When used, the queue is bounded, private, excluded from backups,
and cleared on opt-out; events already sent or OS logs already written cannot be
recalled. See `docs/ANALYTICS.md` for the exact event and delivery contract.
