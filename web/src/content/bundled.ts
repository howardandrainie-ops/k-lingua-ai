// 內建教材：直接匯入 iOS 版的教材 JSON（同一份檔案，兩個版本內容永遠一致）。
import type { CourseUnit, DiagnosticTest } from '../core/content'
import { ContentLibrary } from '../core/library'
import u01 from '../../../Packages/KLinguaCore/Sources/KLinguaCore/Content/unit01.json'
import u02 from '../../../Packages/KLinguaCore/Sources/KLinguaCore/Content/unit02.json'
import u03 from '../../../Packages/KLinguaCore/Sources/KLinguaCore/Content/unit03.json'
import u04 from '../../../Packages/KLinguaCore/Sources/KLinguaCore/Content/unit04.json'
import u05 from '../../../Packages/KLinguaCore/Sources/KLinguaCore/Content/unit05.json'
import u06 from '../../../Packages/KLinguaCore/Sources/KLinguaCore/Content/unit06.json'
import u07 from '../../../Packages/KLinguaCore/Sources/KLinguaCore/Content/unit07.json'
import u08 from '../../../Packages/KLinguaCore/Sources/KLinguaCore/Content/unit08.json'
import u09 from '../../../Packages/KLinguaCore/Sources/KLinguaCore/Content/unit09.json'
import u10 from '../../../Packages/KLinguaCore/Sources/KLinguaCore/Content/unit10.json'
import u11 from '../../../Packages/KLinguaCore/Sources/KLinguaCore/Content/unit11.json'
import u12 from '../../../Packages/KLinguaCore/Sources/KLinguaCore/Content/unit12.json'
import diagnostic from '../../../Packages/KLinguaCore/Sources/KLinguaCore/Content/diagnostic.json'

export const BUNDLED_UNITS = [u01, u02, u03, u04, u05, u06, u07, u08, u09, u10, u11, u12] as unknown as CourseUnit[]
export const BUNDLED_DIAGNOSTIC = diagnostic as unknown as DiagnosticTest

export function loadBundledLibrary(): ContentLibrary {
  return new ContentLibrary(BUNDLED_UNITS, BUNDLED_DIAGNOSTIC)
}
