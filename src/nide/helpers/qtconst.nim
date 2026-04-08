## Qt enum constants used throughout the codebase.
## These replace raw cint literals with descriptive names.

# ── Key codes ──────────────────────────────────────────────────────────────
const
  Key_Escape*    = cint 0x01000000
  Key_Tab*       = cint 0x01000001
  Key_Backspace* = cint 0x01000003
  Key_Return*    = cint 0x01000004
  Key_Enter*     = cint 0x01000005
  Key_Delete*    = cint 0x01000007
  Key_Shift*     = cint 0x01000020
  Key_Control*   = cint 0x01000021
  Key_Meta*      = cint 0x01000023
  Key_N*         = cint 0x4E
  Key_P*         = cint 0x50

# ── Window flags / widget attributes ──────────────────────────────────────
const
  WF_FramelessWindowHint* = cint 0x00000001
  WF_Popup*               = cint 0x00000008
  WF_PopupFrameless*      = cint(0x00000008 or 0x00000001)
  WF_Tool*                = cint 0x00000008
  WF_CustomizeWindowHint* = cint 0x00000080
  WF_WindowTitleHint*     = cint 0x00000001
  WA_TranslucentBackground* = cint 120

# ── Focus policy ──────────────────────────────────────────────────────────
const
  FP_ClickFocus* = cint 2

# ── Shortcut context ─────────────────────────────────────────────────────
const
  SC_WidgetWithChildrenShortcut* = cint 1
  SC_WindowShortcut*             = cint 2

# ── Orientation ──────────────────────────────────────────────────────────
const
  Horizontal* = cint 1
  Vertical*   = cint 2

# ── Size policy ──────────────────────────────────────────────────────────
const
  SP_Minimum*   = cint 0
  SP_Preferred* = cint 5
  SP_Expanding* = cint 7

# ── Text format / interaction ────────────────────────────────────────────
const
  TF_RichText*                      = cint 1
  TIF_TextSelectableByMouse*        = cint 1
  TIF_TextSelectableByKeyboard*     = cint 2
  TIF_TextSelectableAll*            = cint 3

# ── Alignment ────────────────────────────────────────────────────────────
const
  AlignRightVCenter*   = cint 0x0022
  AlignHCenterVCenter* = cint 132

# ── Scroll bar policy ────────────────────────────────────────────────────
const
  SBP_AlwaysOff* = cint 0

# ── Frame style ──────────────────────────────────────────────────────────
const
  NoFrame* = cint 0

# ── QTextCursor move operations ──────────────────────────────────────────
const
  TC_EndOfWord*   = cint 14
  TC_Right*       = cint 19

# ── QTextCursor move modes ───────────────────────────────────────────────
const
  TM_MoveAnchor* = cint 0
  TM_KeepAnchor* = cint 1

# ── QTextCharFormat underline style ──────────────────────────────────────
const
  UL_SpellCheckUnderline* = cint 7

# ── QProcess channel mode ────────────────────────────────────────────────
const
  PC_MergedChannels* = cint 1

# ── QIODevice / QAbstractSocket ──────────────────────────────────────────
const
  IO_ReadWrite*     = cint 3
  AS_IPv4Protocol*  = cint 0

# ── QInputDialog ─────────────────────────────────────────────────────────
const
  ID_TextInput* = cint 0

# ── Drag-drop ────────────────────────────────────────────────────────────
const
  DD_MoveAction*     = cint 2
  DD_InternalMove*   = cint 4
  DD_NoEditTriggers* = cint 0

# ── Header resize mode ───────────────────────────────────────────────────
const
  HR_Stretch*          = cint 1
  HR_ResizeToContents* = cint 1
  HR_Fixed*            = cint 2

# ── Selection behavior ───────────────────────────────────────────────────
const
  SB_SelectRows* = cint 1

# ── Mouse buttons ────────────────────────────────────────────────────────
const
  MB_LeftButton*    = cint 1
  MB_BackButton*    = cint 8
  MB_ForwardButton* = cint 16
  ControlModifier*  = cint 67108864

# ── Item flags ───────────────────────────────────────────────────────────
const
  IF_SelectableEnabled* = cint 0x21

# ── QMessageBox buttons ─────────────────────────────────────────────────
const
  MsgBox_Yes*     = cint 16384
  MsgBox_Cancel*  = cint 4194304
  MsgBox_Save*    = cint 2048
  MsgBox_Discard* = cint 8388608

# ── QDialogButtonBox buttons ────────────────────────────────────────────
const
  Btn_Ok*       = cint 1024
  Btn_Cancel*   = cint 4194304
  Btn_OkCancel* = cint(1024 or 4194304)

# ── QFrame ───────────────────────────────────────────────────────────────
const
  QF_Box*   = cint 1
  QF_Plain* = cint 1

# ── QDialogButtonBox (alternate flag combinations) ──────────────────────
const
  Btn_OkCancel2* = cint(0x00000400 or 0x00400000)
