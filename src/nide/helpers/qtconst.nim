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
  Key_Left*      = cint 0x01000012
  Key_Right*     = cint 0x01000014
  Key_Up*        = cint 0x01000013
  Key_Down*      = cint 0x01000015
  Key_Home*      = cint 0x01000010
  Key_End*       = cint 0x01000011
  Key_PageUp*    = cint 0x01000016
  Key_PageDown*  = cint 0x01000017
  Key_Space*     = cint 0x01000032
  Key_S*         = cint 0x53
  Key_F*         = cint 0x46

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
  FP_ClickFocus*  = cint 2
  FP_StrongFocus* = cint 11

# ── Shortcut context ─────────────────────────────────────────────────────
const
  SC_WidgetShortcut*             = cint 0
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
  TC_StartOfLine*   = cint 0
  TC_EndOfLine*     = cint 1
  TC_StartOfWord*   = cint 2
  TC_EndOfWord*     = cint 14
  TC_Left*          = cint 12
  TC_Right*         = cint 13
  TC_Up*            = cint 4
  TC_Down*          = cint 5
  TC_NextChar*      = cint 8
  TC_PreviousChar* = cint 9
  TC_NextBlock*     = cint 6
  TC_PreviousBlock* = cint 7

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

# ── Header resize mode ───────────────────────────────────────────────────
const
  HR_Stretch*          = cint 1
  HR_ResizeToContents* = cint 1
  HR_Fixed*            = cint 2

# ── Selection behavior ───────────────────────────────────────────────────
const
  SB_SelectRows* = cint 1
  SB_SelectItems* = cint 0
  SB_SelectColumns* = cint 2

# ── Mouse buttons ────────────────────────────────────────────────────────
const
  MB_LeftButton*    = cint 1
  MB_RightButton*   = cint 2
  MB_MidButton*     = cint 4
  MB_BackButton*    = cint 8
  MB_ForwardButton* = cint 16
  ControlModifier*  = cint 67108864

# ── Item flags ───────────────────────────────────────────────────────────
const
  IF_SelectableEnabled* = cint 0x21

# ── Item view drag-drop mode ───────────────────────────────────────────
const
  DD_NoAction*          = cint 0
  DD_CopyAction*        = cint 1
  DD_MoveAction*        = cint 2
  DD_LinkAction*        = cint 4
  DD_InternalMove*      = cint 4
  DD_IgnoreAction*      = cint 5
  DD_NoEditTriggers*    = cint 0
  DD_CurrentChanged*    = cint 1
  DD_DoubleClicked*     = cint 2
  DD_SelectedClicked*   = cint 8

# ── Item view edit triggers ─────────────────────────────────────────────
const
  ET_NoEditTriggers*      = cint 0
  ET_CurrentChanged*      = cint 1
  ET_DoubleClicked*       = cint 2
  ET_SelectedClicked*     = cint 4
  ET_EditKeyPressed*      = cint 8
  ET_AnyKeyPressed*       = cint 32
  ET_AllEditTriggers*    = cint 47

# ── Item view selection mode ─────────────────────────────────────────────
const
  SM_NoSelection*           = cint 0
  SM_SingleSelection*        = cint 1
  SM_MultiSelection*         = cint 2
  SM_ExtendedSelection*      = cint 3
  SM_ContiguousSelection*    = cint 4

# ── QMessageBox buttons ─────────────────────────────────────────────────
const
  MsgBox_Yes*     = cint 16384
  MsgBox_Cancel*  = cint 4194304
  MsgBox_Save*    = cint 2048
  MsgBox_Discard* = cint 8388608
  MsgBox_Ok*      = cint 1024

# ── QDialogButtonBox buttons ────────────────────────────────────────────
const
  Btn_Ok*       = cint 1024
  Btn_Cancel*   = cint 4194304
  Btn_OkCancel* = cint(1024 or 4194304)
  Btn_OkCancel2* = cint(0x00000400 or 0x00400000)
  Btn_Close*    = cint 67108864

# ── QFrame ───────────────────────────────────────────────────────────────
const
  QF_Box*   = cint 1
  QF_Plain* = cint 1

# ── Aspect ratio / image transformation ─────────────────────────────────
const
  KeepAspectRatio*    = cint 1
  FastTransformation* = cint 0
  SmoothTransformation* = cint 1
