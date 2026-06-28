import Foundation
import MacSyncCore

let app = MacSyncApp()
let status = app.run()
if status != 0 {
    Foundation.exit(Int32(status))
}
