# HSBottomSheet

Usage

            var controller = controller()
            sizes.append(SheetSize.fullScreen)
            
            let bottomSheet = HSBottomSheet(controller: controller, sizes: sizes)
            bottomSheet.adjustForBottomSafeArea = false
            bottomSheet.blurBottomSafeArea = true
            bottomSheet.dismissOnBackgroundTap = true
            bottomSheet.extendBackgroundBehindHandle = false
            bottomSheet.topCornersRadius = 15
            
            bottomSheet.willDismiss = { _ in
                print("Will dismiss \(name)")
            }
            bottomSheet.didDismiss = { _ in
                print("Will dismiss \(name)")
            }
            
            self.present(bottomSheet, animated: false, completion: nil)
