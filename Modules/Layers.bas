Attribute VB_Name = "Layers"
'***************************************************************************
'Layer Interface
'Copyright 2014-2019 by Tanner Helland
'Created: 24/March/14
'Last updated: 04/July/14
'Last update: added eraseLayerByIndex() function
'
'This module provides all layer-related functions that interact with PhotoDemon's central processor.  Most of these
' functions are triggered by either the Layer menu, or the Layer toolbox.
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit https://photodemon.org/license/
'
'***************************************************************************

Option Explicit

'Used when converting layers to standalone images and vice-versa
Private Type LayerConvertCache
    Id As Long
    MustConvert As Boolean
    srcLayerName As String
End Type
    
'XML-based wrapper for AddBlankLayer(), below
Public Sub AddBlankLayer_XML(ByRef processParameters As String)
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    cParams.SetParamString processParameters
    Layers.AddBlankLayer cParams.GetLong("targetlayer", PDImages.GetActiveImage.GetActiveLayerIndex), cParams.GetLong("layertype", PDL_IMAGE)
End Sub

'Add a blank 32bpp layer above the specified layer index (typically the currently active layer)
Public Sub AddBlankLayer(ByVal dLayerIndex As Long, Optional ByVal newLayerType As PD_LayerType = PDL_IMAGE)

    'Validate the requested layer index
    If (dLayerIndex < 0) Then dLayerIndex = 0
    If (dLayerIndex > PDImages.GetActiveImage.GetNumOfLayers - 1) Then dLayerIndex = PDImages.GetActiveImage.GetNumOfLayers - 1
    
    'Ask the parent pdImage to create a new layer object
    Dim newLayerID As Long
    newLayerID = PDImages.GetActiveImage.CreateBlankLayer(dLayerIndex)
    
    'Until vector layers are implemented, let's just assign the newly created layer the IMAGE type,
    ' and initialize it to the size of the image.
    Dim tmpDIB As pdDIB
    Set tmpDIB = New pdDIB
    tmpDIB.CreateBlank PDImages.GetActiveImage.Width, PDImages.GetActiveImage.Height, 32, 0, 0
    tmpDIB.SetInitialAlphaPremultiplicationState True
    PDImages.GetActiveImage.GetLayerByID(newLayerID).InitializeNewLayer newLayerType, g_Language.TranslateMessage("Blank layer"), tmpDIB
    
    'Make the blank layer the new active layer
    PDImages.GetActiveImage.SetActiveLayerByID newLayerID
    
    'Notify the parent of the change
    PDImages.GetActiveImage.NotifyImageChanged UNDO_Image_VectorSafe
    
    'Redraw the layer box, and note that thumbnails need to be re-cached
    toolbar_Layers.NotifyLayerChange
    
    'Render the new image to screen (not technically necessary, but doesn't hurt)
    ViewportEngine.Stage1_InitializeBuffer PDImages.GetActiveImage(), FormMain.MainCanvas(0)
            
    'Synchronize the interface to the new image
    SyncInterfaceToCurrentImage
    
End Sub

'XML-based wrapper for AddNewLayer(), below
Public Sub AddNewLayer_XML(ByRef processParameters As String)
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    cParams.SetParamString processParameters
    With cParams
        Layers.AddNewLayer .GetLong("targetlayer", PDImages.GetActiveImage.GetActiveLayerIndex), .GetLong("layertype", PDL_IMAGE), .GetLong("layersubtype", 0), .GetLong("layercolor", vbBlack), .GetLong("layerposition", 0), .GetBool("activatelayer", True), .GetString("layername")
    End With
End Sub

'Add a non-blank 32bpp layer to the image.  (This function is used by the Add New Layer button on the layer box.)
Public Sub AddNewLayer(ByVal dLayerIndex As Long, ByVal dLayerType As PD_LayerType, ByVal dLayerSubType As Long, ByVal dLayerColor As Long, ByVal dLayerPosition As Long, ByVal dLayerAutoSelect As Boolean, Optional ByVal dLayerName As String = vbNullString, Optional ByVal initialXOffset As Single = 0#, Optional ByVal initialYOffset As Single = 0#, Optional ByVal suspendRedraws As Boolean = False)

    'Before making any changes, make a note of the currently active layer
    Dim prevActiveLayerID As Long
    prevActiveLayerID = PDImages.GetActiveImage.GetActiveLayerID
    
    'Validate the requested layer index
    If (dLayerIndex < 0) Then dLayerIndex = 0
    If (dLayerIndex > PDImages.GetActiveImage.GetNumOfLayers - 1) Then dLayerIndex = PDImages.GetActiveImage.GetNumOfLayers - 1
    
    'Ask the parent pdImage to create a new layer object
    Dim newLayerID As Long
    newLayerID = PDImages.GetActiveImage.CreateBlankLayer(dLayerIndex)
    
    'Assign the newly created layer the IMAGE type, and initialize it to the size of the image
    Dim tmpDIB As pdDIB
    Set tmpDIB = New pdDIB
    
    'The parameters passed to the new DIB vary according to layer type.  Use the specified type to determine how we
    ' initialize the new layer.  (Note that this is only relevant for raster layers.)
    If (dLayerType = PDL_IMAGE) Then
    
        Select Case dLayerSubType
        
            'Transparent (blank)
            Case 0
                tmpDIB.CreateBlank PDImages.GetActiveImage.Width, PDImages.GetActiveImage.Height, 32, 0, 0
            
            'Black
            Case 1
                tmpDIB.CreateBlank PDImages.GetActiveImage.Width, PDImages.GetActiveImage.Height, 32, vbBlack, 255
            
            'White
            Case 2
                tmpDIB.CreateBlank PDImages.GetActiveImage.Width, PDImages.GetActiveImage.Height, 32, vbWhite, 255
            
            'Custom color
            Case 3
                tmpDIB.CreateBlank PDImages.GetActiveImage.Width, PDImages.GetActiveImage.Height, 32, dLayerColor, 255
            
        End Select
        
    Else
    
        'Create a 1x1 transparent DIB to avoid errors; subsequent functions will resize the DIB as required
        tmpDIB.CreateBlank 1, 1, 32, 0, 0
    
    End If
    
    'Layers always start with premultiplied alpha
    tmpDIB.SetInitialAlphaPremultiplicationState True
    
    'Set the layer name
    If (LenB(Trim$(dLayerName)) = 0) Then
    
        Select Case dLayerType
        
            Case PDL_IMAGE
                dLayerName = g_Language.TranslateMessage("Blank layer")
                
            Case PDL_TEXT
                dLayerName = g_Language.TranslateMessage("Text layer")
                
            Case PDL_TYPOGRAPHY
                dLayerName = g_Language.TranslateMessage("Typography layer")
        
        End Select
        
    End If
    
    'Assign the newly created DIB and layer name to the layer object
    PDImages.GetActiveImage.GetLayerByID(newLayerID).InitializeNewLayer dLayerType, dLayerName, tmpDIB
    
    'Apply initial layer offsets
    PDImages.GetActiveImage.GetLayerByID(newLayerID).SetLayerOffsetX initialXOffset
    PDImages.GetActiveImage.GetLayerByID(newLayerID).SetLayerOffsetY initialYOffset
    
    'Some layer types may require extra initialization steps in the future
    Select Case dLayerType
        
        Case PDL_IMAGE
        
        'Set an initial width/height of 1x1
        Case PDL_TEXT, PDL_TYPOGRAPHY
            PDImages.GetActiveImage.GetLayerByID(newLayerID).SetLayerWidth 1!
            PDImages.GetActiveImage.GetLayerByID(newLayerID).SetLayerHeight 1!
        
    End Select
        
    'Activate the new layer
    PDImages.GetActiveImage.SetActiveLayerByID prevActiveLayerID
    
    'Move the layer into position as necessary.
    If (dLayerPosition <> 0) Then
    
        Select Case dLayerPosition
        
            'Place below current layer
            Case 1
                MoveLayerAdjacent PDImages.GetActiveImage.GetLayerIndexFromID(newLayerID), False, False
            
            'Move to top of stack
            Case 2
                MoveLayerToEndOfStack PDImages.GetActiveImage.GetLayerIndexFromID(newLayerID), True, False
            
            'Move to bottom of stack
            Case 3
                MoveLayerToEndOfStack PDImages.GetActiveImage.GetLayerIndexFromID(newLayerID), False, False
        
        End Select
        
        'Note that each of the movement functions, above, will call the necessary interface refresh functions,
        ' so we don't need to manually do it here.
        
    End If
    
    'Make the newly created layer the active layer
    If dLayerAutoSelect Then
        Layers.SetActiveLayerByID newLayerID, False, Not suspendRedraws
    Else
        Layers.SetActiveLayerByID prevActiveLayerID, False, Not suspendRedraws
    End If
    
    'Notify the parent of the change
    PDImages.GetActiveImage.NotifyImageChanged UNDO_Image_VectorSafe
    
    'Redraw the main viewport (if requested)
    If (Not suspendRedraws) Then
        
        ViewportEngine.Stage2_CompositeAllLayers PDImages.GetActiveImage(), FormMain.MainCanvas(0)
        
        'Redraw the layer box, and note that thumbnails need to be re-cached
        toolbar_Layers.NotifyLayerChange
        
    End If
    
End Sub

'Create a new layer from the current composite image, and place it at the top of the layer stack
Public Sub AddLayerFromVisibleLayers()

    'Figure out where the top of the layer stack sits
    Dim topLayerIndex As Long
    topLayerIndex = PDImages.GetActiveImage.GetNumOfLayers - 1
    
    'Ask the parent pdImage to create a new layer object at the top of its stack
    Dim newLayerID As Long
    newLayerID = PDImages.GetActiveImage.CreateBlankLayer(topLayerIndex)
    
    'Retrieve a composite of the current image
    Dim tmpDIB As pdDIB
    PDImages.GetActiveImage.GetCompositedImage tmpDIB, True
    PDImages.GetActiveImage.GetLayerByID(newLayerID).InitializeNewLayer PDL_IMAGE, g_Language.TranslateMessage("Visible"), tmpDIB
    
    'Make the blank layer the new active layer
    PDImages.GetActiveImage.SetActiveLayerByID newLayerID
    
    'Notify the parent of the change
    PDImages.GetActiveImage.NotifyImageChanged UNDO_Image_VectorSafe
    
    'Redraw the layer box, and note that thumbnails need to be re-cached
    toolbar_Layers.NotifyLayerChange
    
    'Render the new image to screen (not technically necessary, but doesn't hurt)
    ViewportEngine.Stage1_InitializeBuffer PDImages.GetActiveImage(), FormMain.MainCanvas(0)
            
    'Synchronize the interface to the new image
    Interface.SyncInterfaceToCurrentImage
    
End Sub

'Load an image file, and add it to the current image as a new layer
Public Sub LoadImageAsNewLayer(ByVal ShowDialog As Boolean, Optional ByVal imagePath As String = vbNullString, Optional ByVal customLayerName As String = vbNullString, Optional ByVal createUndo As Boolean = False)

    'This function handles two cases: retrieving the filename from a common dialog box, and actually
    ' loading the image file and applying it to the current pdImage as a new layer.
    
    'If showDialog is TRUE, we need to get a file path from the user
    If ShowDialog Then
    
        'Retrieve a filepath
        Dim imgFilePath As String
        If FileMenu.PhotoDemon_OpenImageDialog_Simple(imgFilePath, FormMain.hWnd) Then
            Process "New layer from file", False, imgFilePath, UNDO_Image_VectorSafe
        End If
    
    'If showDialog is FALSE, the user has already selected a file, and we just need to load it
    Else
    
        'Prepare a temporary DIB
        Dim tmpDIB As pdDIB
        Set tmpDIB = New pdDIB
        
        'Load the file in question
        If Loading.QuickLoadImageToDIB(imagePath, tmpDIB) Then
            
            'Forcibly convert the new layer to 32bpp
            If (tmpDIB.GetDIBColorDepth = 24) Then tmpDIB.ConvertTo32bpp
            
            'Ask the current image to prepare a blank layer for us
            Dim newLayerID As Long
            newLayerID = PDImages.GetActiveImage.CreateBlankLayer()
            
            'Convert the layer to an IMAGE-type layer and copy the newly loaded DIB's contents into it
            If (LenB(customLayerName) = 0) Then
                PDImages.GetActiveImage.GetLayerByID(newLayerID).InitializeNewLayer PDL_IMAGE, Trim$(Files.FileGetName(imagePath, True)), tmpDIB
            Else
                PDImages.GetActiveImage.GetLayerByID(newLayerID).InitializeNewLayer PDL_IMAGE, customLayerName, tmpDIB
            End If
            
            'Debug.Print "Layer created successfully (ID# " & PDImages.GetActiveImage.GetLayerByID(newLayerID).GetLayerName & ")"
            
            'Notify the parent image that the entire image now needs to be recomposited
            PDImages.GetActiveImage.NotifyImageChanged UNDO_Image_VectorSafe
            
            'If the caller wants us to manually create an Undo point (as required when pasting, for example), do so now
            If createUndo Then
                
                Dim tmpProcCall As PD_ProcessCall
                With tmpProcCall
                    .pcID = g_Language.TranslateMessage("New layer from file")
                    .pcParameters = vbNullString
                    .pcRaiseDialog = False
                    .pcRecorded = True
                    .pcUndoType = UNDO_Image_VectorSafe
                End With
                
                PDImages.GetActiveImage.UndoManager.CreateUndoData tmpProcCall, PDImages.GetActiveImage.GetActiveLayerID
                
            End If
            
            'Render the new image to screen
            ViewportEngine.Stage1_InitializeBuffer PDImages.GetActiveImage(), FormMain.MainCanvas(0)
            
            'Synchronize the interface to the new image
            SyncInterfaceToCurrentImage
            
            Message "New layer added successfully."
        
        Else
            PDDebug.LogAction "Image file could not be loaded as new layer.  (User cancellation is one possible outcome, FYI.)"
        End If
    
    End If

End Sub

'Make a given layer fully transparent.  This is used by the Edit > Cut menu at present, if the user cuts without first making a selection.
Public Sub EraseLayerByIndex(ByVal layerIndex As Long)

    If PDImages.IsImageActive() Then
    
        'How we "clear" the layer varies by layer type
        Select Case PDImages.GetActiveImage.GetLayerByIndex(layerIndex).GetLayerType
        
            'For image layers, force the layer DIB to all zeroes
            Case PDL_IMAGE
                With PDImages.GetActiveImage.GetLayerByIndex(layerIndex)
                    .layerDIB.CreateBlank .GetLayerWidth(False), .GetLayerHeight(False), 32, 0, 0
                End With
            
            'For text layers, simply erase the current text.  (This has the effect of making the layer fully transparent,
            ' while retaining all text settings... I'm not sure of a better solution at present.)
            Case PDL_TEXT, PDL_TYPOGRAPHY
                With PDImages.GetActiveImage.GetLayerByIndex(layerIndex)
                    .SetTextLayerProperty ptp_Text, vbNullString
                End With
        
        End Select
        
        'Notify the parent object of the change
        PDImages.GetActiveImage.NotifyImageChanged UNDO_Layer, layerIndex
    
    End If

End Sub

'Reverse the order of layers in this image
Public Sub ReverseLayerOrder()
    If PDImages.IsImageNonNull() Then PDImages.GetActiveImage.ReverseLayerOrder
End Sub

'Select a neighboring layer (up or down)
Public Sub SelectLayerAdjacent(ByVal layerDirectionIsUp As Boolean)

    Dim curLayerIndex As Long
    curLayerIndex = PDImages.GetActiveImage.GetActiveLayerIndex
    
    'Determine a new, valid layer index (with wrapping around top/bottom)
    If layerDirectionIsUp Then curLayerIndex = curLayerIndex + 1 Else curLayerIndex = curLayerIndex - 1
    If (curLayerIndex < 0) Then curLayerIndex = PDImages.GetActiveImage.GetNumOfLayers - 1
    If (curLayerIndex >= PDImages.GetActiveImage.GetNumOfLayers) Then curLayerIndex = 0
    
    'Select the new layer
    Layers.SetActiveLayerByIndex curLayerIndex, True, False

End Sub

'Select the top or bottom layer in this image
Public Sub SelectLayerTopBottom(ByVal topIsWanted As Boolean)

    'Determine a new, valid layer index (with wrapping around top/bottom)
    Dim curLayerIndex As Long
    If topIsWanted Then curLayerIndex = PDImages.GetActiveImage.GetNumOfLayers - 1 Else curLayerIndex = 0
    
    'Select the new layer
    Layers.SetActiveLayerByIndex curLayerIndex, True, False

End Sub

'Activate a layer.  Use this instead of directly calling the pdImage.setActiveLayer function if you want to also
' synchronize the UI to match.
Public Sub SetActiveLayerByID(ByVal newLayerID As Long, Optional ByVal alsoRedrawViewport As Boolean = False, Optional ByVal alsoSyncInterface As Boolean = True)

    'If this layer is already active, ignore the request
    If (PDImages.GetActiveImage.GetActiveLayerID <> newLayerID) Then
        
        'Check for any non-destructive property changes to the previously active layer
        'Processor.FlagFinalNDFXState_Generic pgp_Visibility, PDImages.GetActiveImage.GetActiveLayer.GetLayerVisibility, PDImages.GetActiveImage.GetActiveLayerID
        
        'Notify the parent PD image of the change
        PDImages.GetActiveImage.SetActiveLayerByID newLayerID
        
        'Notify the Undo/Redo engine of all non-destructive property values for the newly activated layer.
        Processor.SyncAllGenericLayerProperties PDImages.GetActiveImage.GetActiveLayer
        If PDImages.GetActiveImage.GetActiveLayer.IsLayerText Then Processor.SyncAllTextLayerProperties PDImages.GetActiveImage.GetActiveLayer
        
        'Sync the interface to the new layer
        If alsoSyncInterface Then SyncInterfaceToCurrentImage
        
        'Redraw the viewport, but only if requested
        If alsoRedrawViewport Then ViewportEngine.Stage2_CompositeAllLayers PDImages.GetActiveImage(), FormMain.MainCanvas(0)
        
    End If
        
End Sub

'Same idea as setActiveLayerByID, above
Public Sub SetActiveLayerByIndex(ByVal newLayerIndex As Long, Optional ByVal alsoRedrawViewport As Boolean = False, Optional ByVal alsoSyncInterface As Boolean = True)

    'If this layer is already active, ignore the request
    If (PDImages.GetActiveImage.GetActiveLayerID <> PDImages.GetActiveImage.GetLayerByIndex(newLayerIndex).GetLayerID) Then
        
        'Check for any non-destructive property changes to the previously active layer
        'Processor.FlagFinalNDFXState_Generic pgp_Visibility, PDImages.GetActiveImage.GetActiveLayer.GetLayerVisibility, PDImages.GetActiveImage.GetActiveLayerID
        
        'Notify the parent PD image of the change
        PDImages.GetActiveImage.SetActiveLayerByIndex newLayerIndex
        
        'Notify the Undo/Redo engine of all non-destructive property values for the newly activated layer.
        Processor.SyncAllGenericLayerProperties PDImages.GetActiveImage.GetActiveLayer
        If PDImages.GetActiveImage.GetActiveLayer.IsLayerText Then Processor.SyncAllTextLayerProperties PDImages.GetActiveImage.GetActiveLayer
        
        'Sync the interface to the new layer
        If alsoSyncInterface Then SyncInterfaceToCurrentImage
            
        'Redraw the viewport, but only if requested
        If alsoRedrawViewport Then ViewportEngine.Stage2_CompositeAllLayers PDImages.GetActiveImage(), FormMain.MainCanvas(0)
        
    End If
        
End Sub

'Make all layers visible or hidden
Public Sub SetLayerVisibility_AllLayers(Optional ByVal isLayerVisible As Boolean = True)
    
    Dim i As Long
    For i = 0 To PDImages.GetActiveImage.GetNumOfLayers - 1
        PDImages.GetActiveImage.GetLayerByIndex(i).SetLayerVisibility isLayerVisible
    Next i
    
    PDImages.GetActiveImage.NotifyImageChanged UNDO_ImageHeader
    
End Sub

'Set layer visibility.  Note that the layer's visibility state must be explicitly noted, e.g. there is no "toggle" option.
Public Sub SetLayerVisibilityByIndex(ByVal dLayerIndex As Long, ByVal layerVisibility As Boolean, Optional ByVal alsoRedrawViewport As Boolean = False)
    
    'Store the new visibility setting in the parent pdImage object
    PDImages.GetActiveImage.GetLayerByIndex(dLayerIndex).SetLayerVisibility layerVisibility
    
    'Notify the parent image of the change
    PDImages.GetActiveImage.NotifyImageChanged UNDO_LayerHeader, dLayerIndex
    
    'Redraw the layer box, but note that thumbnails don't need to be re-cached
    toolbar_Layers.NotifyLayerChange PDImages.GetActiveImage.GetLayerByIndex(dLayerIndex).GetLayerID
    
    'Synchronize the interface to the new image
    SyncInterfaceToCurrentImage
    
    'Redraw the viewport, but only if requested
    If alsoRedrawViewport Then ViewportEngine.Stage2_CompositeAllLayers PDImages.GetActiveImage(), FormMain.MainCanvas(0)
    
End Sub

'Make only one layer visible; all others will be hidden
Public Sub MakeJustOneLayerHidden(ByVal dLayerIndex As Long)
    
    Dim i As Long
    For i = 0 To PDImages.GetActiveImage.GetNumOfLayers - 1
        PDImages.GetActiveImage.GetLayerByIndex(i).SetLayerVisibility (i <> dLayerIndex)
    Next i
    
    PDImages.GetActiveImage.NotifyImageChanged UNDO_ImageHeader
    
End Sub

'Make only one layer visible; all others will be hidden
Public Sub MakeJustOneLayerVisible(ByVal dLayerIndex As Long)
    
    Dim i As Long
    For i = 0 To PDImages.GetActiveImage.GetNumOfLayers - 1
        PDImages.GetActiveImage.GetLayerByIndex(i).SetLayerVisibility (i = dLayerIndex)
    Next i
    
    PDImages.GetActiveImage.NotifyImageChanged UNDO_ImageHeader
    
End Sub

'XML-based wrapper for DuplicateLayerByIndex(), below
Public Sub DuplicateLayerByIndex_XML(ByRef processParameters As String)
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    cParams.SetParamString processParameters
    Layers.DuplicateLayerByIndex cParams.GetLong("targetlayer", PDImages.GetActiveImage.GetActiveLayerIndex)
End Sub

'Duplicate a given layer (note: it doesn't have to be the active layer)
Public Sub DuplicateLayerByIndex(ByVal dLayerIndex As Long)

    'Validate the requested layer index
    If (dLayerIndex < 0) Then dLayerIndex = 0
    If (dLayerIndex > PDImages.GetActiveImage.GetNumOfLayers - 1) Then dLayerIndex = PDImages.GetActiveImage.GetNumOfLayers - 1
    
    'Before doing anything else, make a copy of the current active layer ID.  We will use this to restore the same
    ' active layer after the creation is complete.
    Dim activeLayerID As Long
    activeLayerID = PDImages.GetActiveImage.GetActiveLayerID
    
    'Also copy the ID of the layer we are creating.
    Dim dupedLayerID As Long
    dupedLayerID = PDImages.GetActiveImage.GetLayerByIndex(dLayerIndex).GetLayerID
    
    'Ask the parent pdImage to create a new layer object
    Dim newLayerID As Long
    newLayerID = PDImages.GetActiveImage.CreateBlankLayer(dLayerIndex)
            
    'Ask the new layer to copy the contents of the layer we are duplicating
    PDImages.GetActiveImage.GetLayerByID(newLayerID).CopyExistingLayer PDImages.GetActiveImage.GetLayerByID(dupedLayerID)
    
    'Make the duplicate layer the active layer
    PDImages.GetActiveImage.SetActiveLayerByID newLayerID
    
    'Notify the parent image that the entire image now needs to be recomposited
    PDImages.GetActiveImage.NotifyImageChanged UNDO_Image_VectorSafe
    
    'Redraw the layer box, and note that thumbnails need to be re-cached
    toolbar_Layers.NotifyLayerChange
    
    'Render the new image to screen
    ViewportEngine.Stage1_InitializeBuffer PDImages.GetActiveImage(), FormMain.MainCanvas(0)
            
    'Synchronize the interface to the new image
    Interface.SyncInterfaceToCurrentImage
    
End Sub

'Merge the layer at layerIndex up or down.
Public Sub MergeLayerAdjacent(ByVal dLayerIndex As Long, ByVal mergeDown As Boolean)

    'Look for a valid target layer to merge with in the requested direction.
    Dim mergeTarget As Long
    mergeTarget = IsLayerAllowedToMergeAdjacent(dLayerIndex, mergeDown)
    
    'If we've been given a valid merge target, apply it now!
    If (mergeTarget >= 0) Then
    
        If mergeDown Then
        
            With PDImages.GetActiveImage()
                
                'Request a merge from the parent pdImage
                .MergeTwoLayers .GetLayerByIndex(dLayerIndex), .GetLayerByIndex(mergeTarget), False
                
                'Delete the now-merged layer
                .DeleteLayerByIndex dLayerIndex
                
                'Notify the parent of the change
                .NotifyImageChanged UNDO_Layer, mergeTarget
                
                'Set the newly merged layer as the active layer
                .SetActiveLayerByIndex mergeTarget
            
            End With
            
        Else
        
            With PDImages.GetActiveImage()
            
                'Request a merge from the parent pdImage
                .MergeTwoLayers .GetLayerByIndex(mergeTarget), .GetLayerByIndex(dLayerIndex), False
                
                'Delete the now-merged layer
                .DeleteLayerByIndex mergeTarget
                
                'Notify the parent of the change
                .NotifyImageChanged UNDO_Layer, dLayerIndex
                
                'Set the newly merged layer as the active layer
                .SetActiveLayerByIndex dLayerIndex
                
            End With
        
        End If
                
        'Redraw the layer box, and note that thumbnails need to be re-cached
        toolbar_Layers.NotifyLayerChange
        
        'Redraw the viewport
        ViewportEngine.Stage2_CompositeAllLayers PDImages.GetActiveImage(), FormMain.MainCanvas(0)
        
    End If

End Sub

'Is this layer allowed to merge up or down?  Note that invisible layers are not generally considered suitable
' for merging, so a layer will typically be merged with the next VISIBLE layer.  If none are available, merging
' is disallowed.
'
'Note that the return value for this function is a little wonky.  This function will return the TARGET MERGE LAYER
' INDEX if the function is successful.  This value will always be >= 0.  If no valid layer can be found, -1 will be
' returned (which obviously isn't a valid index, but IS true, so it's a little confusing - handle accordingly!)
'
'It should be obvious, but the parameter srcLayerIndex is the index of the layer the caller wants to merge.
Public Function IsLayerAllowedToMergeAdjacent(ByVal srcLayerIndex As Long, ByVal moveDown As Boolean) As Long

    Dim i As Long
    
    'First, make sure the layer in question exists
    If Not PDImages.GetActiveImage.GetLayerByIndex(srcLayerIndex) Is Nothing Then
    
        'Check MERGE DOWN
        If moveDown Then
        
            'As an easy check, make sure this layer is visible, and not already at the bottom.
            If (srcLayerIndex <= 0) Or (Not PDImages.GetActiveImage.GetLayerByIndex(srcLayerIndex).GetLayerVisibility) Then
                IsLayerAllowedToMergeAdjacent = -1
                Exit Function
            End If
            
            'Search for the nearest valid layer beneath this one.
            For i = srcLayerIndex - 1 To 0 Step -1
                If PDImages.GetActiveImage.GetLayerByIndex(i).GetLayerVisibility Then
                    IsLayerAllowedToMergeAdjacent = i
                    Exit Function
                End If
            Next i
            
            'If we made it all the way here, no valid merge target was found.  Return failure (-1).
            IsLayerAllowedToMergeAdjacent = -1
        
        'Check MERGE UP
        Else
        
            'As an easy check, make sure this layer isn't already at the top.
            If (srcLayerIndex >= PDImages.GetActiveImage.GetNumOfLayers - 1) Or (Not PDImages.GetActiveImage.GetLayerByIndex(srcLayerIndex).GetLayerVisibility) Then
                IsLayerAllowedToMergeAdjacent = -1
                Exit Function
            End If
            
            'Search for the nearest valid layer above this one.
            For i = srcLayerIndex + 1 To PDImages.GetActiveImage.GetNumOfLayers - 1
                If PDImages.GetActiveImage.GetLayerByIndex(i).GetLayerVisibility Then
                    IsLayerAllowedToMergeAdjacent = i
                    Exit Function
                End If
            Next i
            
            'If we made it all the way here, no valid merge target was found.  Return failure (-1).
            IsLayerAllowedToMergeAdjacent = -1
        
        End If
        
    End If

End Function

Public Function SplitLayerToImage(Optional ByRef processParameters As String) As Boolean
    
    SplitLayerToImage = False
    
    'Retrieve any conversion parameters
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    cParams.SetParamString processParameters
    
    Dim targetIndex As Long
    targetIndex = cParams.GetLong("target-layer", -1)
    
    'Process parameters specify *which* layer(s) should be converted to a standalone image.
    ' Layers are identified by index.  We want to handle the conversion in two steps:
    ' 1) Convert all layer(s) to standalone images
    ' 2) Remove all converted layer(s) from the current image (typically, all but the active layer)
    Dim i As Long
    
    'Make a safe local reference to the currently active image - because the active image will
    ' change as we load other images.
    Dim srcImage As pdImage
    Set srcImage = PDImages.GetActiveImage
    
    'To simplify this process, construct an array that identifies all layers by their ID
    ' (which is immutable, and will not change - unlike layer indices)
    With srcImage
        
        Dim listOfLayers() As LayerConvertCache
        ReDim listOfLayers(0 To .GetNumOfLayers - 1) As LayerConvertCache
        
        For i = 0 To .GetNumOfLayers - 1
            
            listOfLayers(i).Id = .GetLayerByIndex(i).GetLayerID
            
            If (targetIndex = -1) Then
                listOfLayers(i).MustConvert = True
            Else
                listOfLayers(i).MustConvert = (i = targetIndex)
            End If
            
        Next i
        
    End With
    
    'We now have a list which layers require converting.  Iterate through each layer,
    ' convert it to a null-padded layer (which greatly simplifies re-assembly later),
    ' split it into a separate image, then remove it from the image.
    For i = 0 To UBound(listOfLayers)
    
        If listOfLayers(i).MustConvert Then
            
            Message "Copying layer ""%1"" to standalone image...", srcImage.GetLayerByID(listOfLayers(i).Id).GetLayerName()
            
            Dim tmpLayer As pdLayer
            Set tmpLayer = New pdLayer
            tmpLayer.CopyExistingLayer srcImage.GetLayerByID(listOfLayers(i).Id)
            tmpLayer.SetLayerName srcImage.GetLayerByID(listOfLayers(i).Id).GetLayerName()
            
            'Convert the layer to a null-padded layer (a layer at the same size as the current image)
            tmpLayer.ConvertToNullPaddedLayer srcImage.Width, srcImage.Height
            
            'Load said layer as a separate image
            Dim tmpLayerFile As String
            tmpLayerFile = UserPrefs.GetTempPath & "LayerConvert.pdi"
            
            Dim tmpImage As pdImage
            Set tmpImage = New pdImage
            
            'In the temporary pdImage object, create a blank layer; this will receive the processed DIB
            Dim newLayerID As Long
            newLayerID = tmpImage.CreateBlankLayer
            tmpImage.GetLayerByID(newLayerID).CopyExistingLayer tmpLayer
            
            'Ensure the layer name(s) match - we may use this later to reassemble the separate images
            ' back into a stacked image
            tmpImage.GetLayerByID(newLayerID).SetLayerName tmpLayer.GetLayerName()
            tmpImage.UpdateSize
            
            'Write the image out to file, then free its associated memory
            Saving.SavePhotoDemonImage tmpImage, tmpLayerFile, True, cf_Lz4, cf_Lz4
            Set tmpImage = Nothing
            
            'Construct a title (name) for the new image, and insert the original layer index.
            ' (This is helpful if the user decides to reconstruct the layers into an image later.)
            Dim sTitle As String
            sTitle = tmpLayer.GetLayerName()
            If (LenB(sTitle) = 0) Then sTitle = g_Language.TranslateMessage("[untitled image]")
            Set tmpLayer = Nothing
            
            'We can now use the standard image load routine to import the temporary file
            Loading.LoadFileAsNewImage tmpLayerFile, sTitle, False, , False
            
            'Be polite and remove the temporary file
            Files.FileDeleteIfExists tmpLayerFile
            
        End If
    
    Next i
    
    SplitLayerToImage = True
    Message "Conversion complete."
            
End Function

'XML-based wrapper to DeleteLayer(), below
Public Sub DeleteLayer_XML(ByRef processParameters As String)
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    cParams.SetParamString processParameters
    Layers.DeleteLayer cParams.GetLong("layerindex", PDImages.GetActiveImage.GetActiveLayerIndex)
End Sub

'Delete a given layer
Public Sub DeleteLayer(ByVal dLayerIndex As Long, Optional ByVal updateUI As Boolean = True)

    'Cache the current layer index
    Dim curLayerIndex As Long
    curLayerIndex = PDImages.GetActiveImage.GetActiveLayerIndex - 1

    PDImages.GetActiveImage.DeleteLayerByIndex dLayerIndex
    
    If updateUI Then
        
        'Set a new active layer
        If (curLayerIndex > PDImages.GetActiveImage.GetNumOfLayers - 1) Then curLayerIndex = PDImages.GetActiveImage.GetNumOfLayers - 1
        If (curLayerIndex < 0) Then curLayerIndex = 0
        SetActiveLayerByIndex curLayerIndex, False
        
        'Notify the parent image that the entire image now needs to be recomposited
        PDImages.GetActiveImage.NotifyImageChanged UNDO_Image_VectorSafe
        
        'Redraw the layer box, and note that thumbnails need to be re-cached
        toolbar_Layers.NotifyLayerChange
        
        'Redraw the viewport
        ViewportEngine.Stage2_CompositeAllLayers PDImages.GetActiveImage(), FormMain.MainCanvas(0)
        
    End If

End Sub

'Delete all hidden layers
Public Sub DeleteHiddenLayers()

    'Perform a couple fail-safe checks.  These should not be a problem, as calling functions should have safeguards
    ' against bad requests, but better safe than sorry.
    
    'If there are no hidden layers, exit
    If PDImages.GetActiveImage.GetNumOfHiddenLayers = 0 Then Exit Sub
    
    'If all layers are hidden, exit
    If PDImages.GetActiveImage.GetNumOfHiddenLayers = PDImages.GetActiveImage.GetNumOfLayers Then Exit Sub
    
    'We can now assume that the image in question has at least one visible layer, and at least one hidden layer.
    
    'Cache the currently active layerID - IF the current layer is visible.  If it isn't, it's going to be deleted,
    ' so we must pick a new arbitrary layer (why not the bottom layer?).
    Dim activeLayerID As Long
    
    If PDImages.GetActiveImage.GetActiveLayer.GetLayerVisibility Then
        activeLayerID = PDImages.GetActiveImage.GetActiveLayerID
    Else
        activeLayerID = -1
    End If
    
    'Starting at the top and moving down, delete all hidden layers.
    Dim i As Long
    For i = PDImages.GetActiveImage.GetNumOfLayers - 1 To 0 Step -1
    
        If Not PDImages.GetActiveImage.GetLayerByIndex(i).GetLayerVisibility Then
            PDImages.GetActiveImage.DeleteLayerByIndex i
        End If
    Next i
    
    'Set a new active layer
    If activeLayerID = -1 Then
        SetActiveLayerByIndex 0, False
    Else
        SetActiveLayerByID activeLayerID
    End If
    
    'Notify the parent image that the entire image now needs to be recomposited
    PDImages.GetActiveImage.NotifyImageChanged UNDO_Image_VectorSafe
    
    'Redraw the layer box, and note that thumbnails need to be re-cached
    toolbar_Layers.NotifyLayerChange
    
    'Redraw the viewport
    ViewportEngine.Stage2_CompositeAllLayers PDImages.GetActiveImage(), FormMain.MainCanvas(0)

End Sub

'Given all open images (besides the current one), assemble them as layers into the current image.
Public Sub MergeImagesToLayers(ByVal showPrompt As Boolean, Optional ByVal processParameters As String = vbNullString)
    
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
            
    If showPrompt Then
    
        Dim msgText As pdString
        Set msgText = New pdString
        msgText.AppendLine g_Language.TranslateMessage("PhotoDemon can automatically match imported images to existing layers with the same name.")
        msgText.AppendLineBreak
        msgText.AppendLine g_Language.TranslateMessage("If matches are found, would you prefer to update existing layers?")
        msgText.AppendLineBreak
        msgText.Append g_Language.TranslateMessage("(If you select ""no"", each imported image will be added as a new layer, even if it matches an existing one.)")
        
        Dim msgResult As VbMsgBoxResult
        msgResult = PDMsgBox(msgText.ToString(), vbInformation Or vbYesNoCancel, "Split images into layers")
        
        If (msgResult = vbCancel) Then
            Exit Sub
        Else
            
            If (msgResult = vbNo) Then
                cParams.AddParam "overwrite-layers", False
            Else
                cParams.AddParam "overwrite-layers", True
            End If
            
            Process "Split images into layers", False, cParams.GetParamString, UNDO_Everything
            
        End If
    
    Else
        
        cParams.SetParamString processParameters
        
        'This function is sort of an odd case for PD, as operations are typically strictly limited
        ' to only affecting the active image.
        
        'First, we want to make a list of open images, and try to figure out where (if any) each
        ' image should be inserted.  This is most relevant when the images were originally split using
        ' the "Split layers into images" command - by parsing layer indices out of their titles, we can
        ' split each image back into its original parent image *at its original location*.
        Dim openImageIDs As pdStack
        If (Not PDImages.GetListOfActiveImageIDs(openImageIDs)) Then Exit Sub
        
        Dim listOfImages() As LayerConvertCache
        ReDim listOfImages(0 To openImageIDs.GetNumOfInts - 1) As LayerConvertCache
        
        Dim localizedTag As String
        
        Dim i As Long
        For i = 0 To UBound(listOfImages)
            
            'We want to convert all images *except* the currently active one
            listOfImages(i).MustConvert = (PDImages.GetImageByID(openImageIDs.GetInt(i)).imageID <> PDImages.GetActiveImageID)
            
            'For each image-to-be-converted...
            If listOfImages(i).MustConvert Then
                
                'Make a note of the image's ID
                listOfImages(i).Id = openImageIDs.GetInt(i)
                
                'Next, pull the name of the base layer.  This is the layer name we want to match
                ' against the layer names in our existing image, to try and identify matches.
                listOfImages(i).srcLayerName = PDImages.GetImageByID(listOfImages(i).Id).GetLayerByIndex(0).GetLayerName()
                
            End If
            
        Next i
        
        'Make a note of the currently active layer index
        Dim activeLayerIndex As Long
        activeLayerIndex = PDImages.GetActiveImage.GetActiveLayerIndex()
        
        'Make a safe local reference to the currently active image - because the active image may
        ' change as we access other images.
        Dim srcImage As pdImage
        Set srcImage = PDImages.GetActiveImage
        
        'Next, we want to make a bool array to track which layer names we have matched so far
        ' (in the active image).  On the off chance that there are 2+ layers with identical names,
        ' we want to match the layers in-order (instead of overwriting the same one twice).
        Dim layerMatched() As Boolean
        ReDim layerMatched(0 To srcImage.GetNumOfLayers - 1) As Boolean
        
        Dim overwriteMatchingLayers As Boolean
        overwriteMatchingLayers = cParams.GetBool("overwrite-layers", False)
        
        'Next, we basically want to iterate through all images in the collection, and add each one
        ' to this image - as a unique layer - in turn.
        For i = 0 To UBound(listOfImages)
            
            If listOfImages(i).MustConvert Then
                
                Message "Adding image ""%1"" as layer...", listOfImages(i).srcLayerName
                
                'Ask the target file to write itself out to a temp PDI file
                Dim tmpLayerFile As String
                tmpLayerFile = UserPrefs.GetTempPath & "LayerConvert.pdi"
                If Saving.SavePhotoDemonImage(PDImages.GetImageByID(listOfImages(i).Id), tmpLayerFile, True, cf_Lz4, cf_Lz4) Then
                    
                    'We now want to load the resulting image as a standalone layer.  We use a convenient
                    ' wrapper function that ensures the image is loaded as a single layer, even if it
                    ' contains multiple layers.  (This is by design, to allow the user to do things like
                    ' overlay text on a single layer, then merge that layer back into a parent image.)
                    Dim tmpDIB As pdDIB
                    Set tmpDIB = New pdDIB
                    If Loading.QuickLoadImageToDIB(tmpLayerFile, tmpDIB, False, False) Then
                        
                        Dim targetIndex As Long
                        targetIndex = -1
                        
                        'Next, try to find a layer with this name in the current image.
                        If overwriteMatchingLayers Then
                            
                            Dim j As Long
                            For j = 0 To srcImage.GetNumOfLayers - 1
                                If Strings.StringsEqual(srcImage.GetLayerByIndex(j).GetLayerName, listOfImages(i).srcLayerName, False) Then
                                    
                                    'Make sure we haven't matched this layer already
                                    If (Not layerMatched(j)) Then
                                        layerMatched(j) = True
                                        targetIndex = j
                                        Exit For
                                    End If
                                        
                                End If
                            Next j
                            
                        End If
                        
                        'Add the new layer to this image in one of two ways:
                        ' 1) If a matching layer name was found in the current image, overwrite that layer
                        '    with the one we've imported from file.
                        Dim mustCreateNewLayer As Boolean
                        mustCreateNewLayer = True
                        If (targetIndex >= 0) Then
                            mustCreateNewLayer = Not layerMatched(targetIndex)
                        End If
                        
                        Dim newLayerID As Long
                        newLayerID = srcImage.CreateBlankLayer(targetIndex)
                        srcImage.GetLayerByID(newLayerID).InitializeNewLayer PDL_IMAGE, listOfImages(i).srcLayerName, tmpDIB, True
                        Set tmpDIB = Nothing
                        
                        If (Not mustCreateNewLayer) Then Layers.DeleteLayer targetIndex, False
                        
                        'Auto-crop the layer, as it will have been null-padded by a previous step
                        srcImage.GetLayerByID(newLayerID).CropNullPaddedLayer
                        
                    End If
                    
                    'Delete the temp file
                    Files.FileDeleteIfExists tmpLayerFile
                
                End If
                
            End If
            
        Next i
        
        'Restore the currently active layer index
        PDImages.GetActiveImage.SetActiveLayerByIndex activeLayerIndex
        
        'Make sure the original image is notified of the new layer arrangement (which prompts it
        ' to update things like its internal thumbnail cache)
        srcImage.NotifyImageChanged UNDO_Image
        
        'Restore the originally active image as the image with focus.  (By default, newly loaded images
        ' "steal" focus - this is a rare case where we don't want that.)
        CanvasManager.ActivatePDImage srcImage.imageID, "Split images into layers", True, , True
        
        Message "Conversion complete."
        
    End If
            
End Sub

'Move a layer up or down in the stack (referred to as "raise" and "lower" in the menus)
Public Sub MoveLayerAdjacent(ByVal dLayerIndex As Long, ByVal directionIsUp As Boolean, Optional ByVal updateInterface As Boolean = True)

    'Make a copy of the currently active layer's ID
    Dim curActiveLayerID As Long
    curActiveLayerID = PDImages.GetActiveImage.GetActiveLayerID
    
    'Ask the parent pdImage to move the layer for us
    PDImages.GetActiveImage.MoveLayerByIndex dLayerIndex, directionIsUp
    
    'Restore the active layer
    SetActiveLayerByID curActiveLayerID, False
    
    'Notify the parent image that the entire image now needs to be recomposited
    PDImages.GetActiveImage.NotifyImageChanged UNDO_Image_VectorSafe
    
    If updateInterface Then
        
        'Redraw the layer box, and note that thumbnails need to be re-cached
        toolbar_Layers.NotifyLayerChange
        
        'Redraw the viewport
        ViewportEngine.Stage2_CompositeAllLayers PDImages.GetActiveImage(), FormMain.MainCanvas(0)
        
    End If

End Sub

'Move a layer to the top or bottom of the stack (referred to as "raise to top" and "lower to bottom" in the menus)
Public Sub MoveLayerToEndOfStack(ByVal dLayerIndex As Long, ByVal moveToTopOfStack As Boolean, Optional ByVal updateInterface As Boolean = True)

    'Make a copy of the currently active layer's ID
    Dim curActiveLayerID As Long
    curActiveLayerID = PDImages.GetActiveImage.GetActiveLayerID
    
    Dim i As Long
    
    'Until this layer is at the desired end of the stack, ask the parent to keep moving it for us!
    If moveToTopOfStack Then
    
        For i = dLayerIndex To PDImages.GetActiveImage.GetNumOfLayers - 1
            
            'Ask the parent pdImage to move the layer up for us
            PDImages.GetActiveImage.MoveLayerByIndex i, True
            
        Next i
    
    Else
    
        For i = dLayerIndex To 0 Step -1
            
            'Ask the parent pdImage to move the layer up for us
            PDImages.GetActiveImage.MoveLayerByIndex i, False
            
        Next i
    
    End If
    
    'Restore the active layer.  (This will also re-synchronize the interface against the new image.)
    SetActiveLayerByID curActiveLayerID, False
    
    'Notify the parent image that the entire image now needs to be recomposited
    PDImages.GetActiveImage.NotifyImageChanged UNDO_Image_VectorSafe
    
    If updateInterface Then
    
        'Redraw the layer box, and note that thumbnails need to be re-cached
        toolbar_Layers.NotifyLayerChange
        
        'Redraw the viewport
        ViewportEngine.Stage2_CompositeAllLayers PDImages.GetActiveImage(), FormMain.MainCanvas(0)
        
    End If

End Sub

'Given a multi-layered image, flatten it.  Note that flattening does *not* remove alpha!  It simply merges all layers,
' including discarding invisible ones.
Public Sub FlattenImage(Optional ByVal functionParams As String = vbNullString)
    
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    cParams.SetParamString functionParams
    
    Dim removeTransparency As Boolean, newBackgroundColor As Long
    removeTransparency = cParams.GetBool("removetransparency", False)
    newBackgroundColor = cParams.GetLong("backgroundcolor", vbWhite)
    
    'Start by retrieving a copy of the composite image
    Dim compositeDIB As pdDIB
    Set compositeDIB = New pdDIB
    
    PDImages.GetActiveImage.GetCompositedImage compositeDIB
    
    'If the caller wants the flattened image to *not* have transparency, remove said transparency now
    If removeTransparency Then compositeDIB.CompositeBackgroundColor Colors.ExtractRed(newBackgroundColor), Colors.ExtractGreen(newBackgroundColor), Colors.ExtractBlue(newBackgroundColor)
    
    'Also, grab the name of the bottom-most layer.  This will be used as the name of our only layer in the flattened image.
    Dim flattenedName As String
    flattenedName = PDImages.GetActiveImage.GetLayerByIndex(0).GetLayerName
    
    'With this information, we can now delete all image layers.
    Do
        PDImages.GetActiveImage.DeleteLayerByIndex 0
    Loop While PDImages.GetActiveImage.GetNumOfLayers > 1
    
    'Note that the delete operation does not allow us to delete all layers.  (If there is only one layer present,
    ' it will exit without modifying the image.)  Because of that, the image will still retain one layer, which
    ' we will have to manually overwrite.
        
    'Reset any optional layer parameters to their default state
    PDImages.GetActiveImage.GetLayerByIndex(0).ResetLayerParameters
    
    'Overwrite the final layer with the composite DIB.
    PDImages.GetActiveImage.GetLayerByIndex(0).InitializeNewLayer PDL_IMAGE, flattenedName, compositeDIB
    
    'Mark the only layer present as the active one.  (This will also re-synchronize the interface against the new image.)
    SetActiveLayerByIndex 0, False
    
    'Notify the parent of the change
    PDImages.GetActiveImage.NotifyImageChanged UNDO_Layer, 0
    PDImages.GetActiveImage.NotifyImageChanged UNDO_Image
    
    'Redraw the layer box, and note that thumbnails need to be re-cached
    toolbar_Layers.NotifyLayerChange
    
    'Redraw the viewport
    ViewportEngine.Stage2_CompositeAllLayers PDImages.GetActiveImage(), FormMain.MainCanvas(0)

End Sub

'Given a multi-layered image, merge all visible layers, while ignoring any hidden ones.  Note that flattening does *not*
' remove alpha!  It simply merges all visible layers.
Public Sub MergeVisibleLayers()
    
    'If there's only one layer, this function should not be called - but just in case, exit in advance.
    If (PDImages.GetActiveImage.GetNumOfLayers = 1) Then Exit Sub
    
    'Similarly, if there's only one *visible* layer, this function should not be called - but just in case, exit in advance.
    If (PDImages.GetActiveImage.GetNumOfVisibleLayers = 1) Then Exit Sub
    
    'By this point, we can assume there are at least two visible layers in the image.  Rather than deal with the messiness
    ' of finding the lowest base layer and gradually merging everything into it, we're going to just create a new blank
    ' layer at the base of the image, then merge everything with it until finally all visible layers have been merged.
    
    'Insert a new layer at the bottom of the layer stack.
    PDImages.GetActiveImage.CreateBlankLayer 0
    
    'Technically, the command above does not actually insert a new layer at the base of the image.  Per convention,
    ' it always inserts the requested layer at the spot one *above* the requested spot.  To work around this, swap
    ' our newly created layer with the layer at position 0.
    PDImages.GetActiveImage.SwapTwoLayers 0, 1
    
    'Fill that new layer with a blank DIB at the dimensions of the image.
    Dim tmpDIB As pdDIB
    Set tmpDIB = New pdDIB
    tmpDIB.CreateBlank PDImages.GetActiveImage.Width, PDImages.GetActiveImage.Height, 32, 0
    tmpDIB.SetAlphaPremultiplication True
    PDImages.GetActiveImage.GetLayerByIndex(0).InitializeNewLayer PDL_IMAGE, g_Language.TranslateMessage("Merged layers"), tmpDIB
    
    'With that done, merging visible layers is actually not that hard.  Loop through the layer collection,
    ' merging visible layers with the base layer, until all visible layers have been merged.
    Dim i As Long
    For i = 1 To PDImages.GetActiveImage.GetNumOfLayers - 1
    
        'If this layer is visible, merge it with the base layer
        If PDImages.GetActiveImage.GetLayerByIndex(i).GetLayerVisibility Then
            PDImages.GetActiveImage.MergeTwoLayers PDImages.GetActiveImage.GetLayerByIndex(i), PDImages.GetActiveImage.GetLayerByIndex(0), True
        End If
    
    Next i
    
    'Now that our base layer contains the result of merging all visible layers, we can now delete all
    ' other visible layers.
    For i = PDImages.GetActiveImage.GetNumOfLayers - 1 To 1 Step -1
        If PDImages.GetActiveImage.GetLayerByIndex(i).GetLayerVisibility Then
            PDImages.GetActiveImage.DeleteLayerByIndex i
        End If
    Next i
    
    'Mark the new merged layer as the active one.  (This will also re-synchronize the interface against the new image.)
    Layers.SetActiveLayerByIndex 0, False
    
    'Notify the parent image that the entire image now needs to be recomposited
    PDImages.GetActiveImage.NotifyImageChanged UNDO_Layer, 0
    PDImages.GetActiveImage.NotifyImageChanged UNDO_Image
    
    'Redraw the layer box, and note that thumbnails need to be re-cached
    toolbar_Layers.NotifyLayerChange
    
    'Redraw the viewport
    ViewportEngine.Stage2_CompositeAllLayers PDImages.GetActiveImage(), FormMain.MainCanvas(0)

End Sub

'If a layer has been transformed using the on-canvas tools, this will reset it to its default size.
Public Sub ResetLayerSize(ByVal srcLayerIndex As Long)

    PDImages.GetActiveImage.GetLayerByIndex(srcLayerIndex).SetLayerCanvasXModifier 1
    PDImages.GetActiveImage.GetLayerByIndex(srcLayerIndex).SetLayerCanvasYModifier 1
    
    'Notify the parent image of the change
    PDImages.GetActiveImage.NotifyImageChanged UNDO_LayerHeader, srcLayerIndex
    
    'Re-sync the interface
    Interface.SyncInterfaceToCurrentImage
    
    'Redraw the viewport
    ViewportEngine.Stage2_CompositeAllLayers PDImages.GetActiveImage(), FormMain.MainCanvas(0)

End Sub

'If a layer has been transformed using the on-canvas tools, this will make those transforms permanent.
Public Sub MakeLayerAffineTransformsPermanent(ByVal srcLayerIndex As Long)
    
    'Layers are capable of making this change internally
    PDImages.GetActiveImage.GetLayerByIndex(srcLayerIndex).MakeCanvasTransformsPermanent
    
    'Notify the parent object of this change
    PDImages.GetActiveImage.NotifyImageChanged UNDO_Layer, srcLayerIndex
    
    'Re-sync the interface
    Interface.SyncInterfaceToCurrentImage
    
    'Redraw the viewport
    ViewportEngine.Stage2_CompositeAllLayers PDImages.GetActiveImage(), FormMain.MainCanvas(0)

End Sub

'If a layer has been rotated using the on-canvas tools, this will reset it to its default orientation.
Public Sub ResetLayerAngle(ByVal srcLayerIndex As Long)

    PDImages.GetActiveImage.GetLayerByIndex(srcLayerIndex).SetLayerAngle 0
    
    'Notify the parent image of the change
    PDImages.GetActiveImage.NotifyImageChanged UNDO_LayerHeader, srcLayerIndex
    
    'Re-sync the interface
    Interface.SyncInterfaceToCurrentImage
    
    'Redraw the viewport
    ViewportEngine.Stage2_CompositeAllLayers PDImages.GetActiveImage(), FormMain.MainCanvas(0)

End Sub

'If a layer has been sheared using the on-canvas tools, this will reset it to shear = 0 for the specified direction.
Public Sub ResetLayerShear(ByVal srcLayerIndex As Long, Optional ByVal shearDirectionHorizontal As Boolean = True)

    'Reset the shear value we were passed
    If shearDirectionHorizontal Then
        PDImages.GetActiveImage.GetLayerByIndex(srcLayerIndex).SetLayerShearX 0
    Else
        PDImages.GetActiveImage.GetLayerByIndex(srcLayerIndex).SetLayerShearY 0
    End If
    
    'Notify the parent image of the change
    PDImages.GetActiveImage.NotifyImageChanged UNDO_LayerHeader, srcLayerIndex
    
    'Re-sync the interface
    Interface.SyncInterfaceToCurrentImage
    
    'Redraw the viewport
    ViewportEngine.Stage2_CompositeAllLayers PDImages.GetActiveImage(), FormMain.MainCanvas(0)

End Sub

'Resize a layer non-destructively, e.g. by only changing its position and on-canvas x/y modifiers
Public Sub ResizeLayerNonDestructive(ByVal srcLayerIndex As Long, ByRef resizeParams As String)

    'Create a parameter parser to help us interpret the passed param string
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    cParams.SetParamString resizeParams
    
    'Apply the passed parameters to the specified layer
    With PDImages.GetActiveImage.GetLayerByIndex(srcLayerIndex)
        .SetLayerOffsetX cParams.GetDouble("layer-offsetx")
        .SetLayerOffsetY cParams.GetDouble("layer-offsety")
        
        'Raster and vector layers use different size descriptors.  (Vector layers use an absolute size; raster layers use the
        ' underlying DIB size, plus a fractional modifier.)
        If (.GetLayerType = PDL_IMAGE) Then
            .SetLayerCanvasXModifier cParams.GetDouble("layer-modifierx")
            .SetLayerCanvasYModifier cParams.GetDouble("layer-modifiery")
        Else
            .SetLayerWidth cParams.GetLong("layer-sizex")
            .SetLayerHeight cParams.GetLong("layer-sizey")
        End If
        
    End With
    
    'Notify the parent image of the change
    PDImages.GetActiveImage.NotifyImageChanged UNDO_LayerHeader, srcLayerIndex
    
    'Redraw the viewport
    ViewportEngine.Stage2_CompositeAllLayers PDImages.GetActiveImage(), FormMain.MainCanvas(0)

End Sub

'Rotate a layer non-destructively, e.g. by only changing its header angle value
Public Sub RotateLayerNonDestructive(ByVal srcLayerIndex As Long, ByRef resizeParams As String)

    'Create a parameter parser to help us interpret the passed param string
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    cParams.SetParamString resizeParams
    
    'Apply the passed parameter to the specified layer
    With PDImages.GetActiveImage.GetLayerByIndex(srcLayerIndex)
        .SetLayerAngle cParams.GetDouble("layer-angle", 0#)
    End With
    
    'Notify the parent image of the change
    PDImages.GetActiveImage.NotifyImageChanged UNDO_LayerHeader, srcLayerIndex
    
    'Redraw the viewport
    ViewportEngine.Stage2_CompositeAllLayers PDImages.GetActiveImage(), FormMain.MainCanvas(0)

End Sub

'Move a layer to a new x/y position on the canvas
Public Sub MoveLayerOnCanvas(ByVal srcLayerIndex As Long, ByRef resizeParams As String)

    'Create a parameter parser to help us interpret the passed param string
    Dim cParams As pdParamXML
    Set cParams = New pdParamXML
    cParams.SetParamString resizeParams
    
    'Apply the passed parameters to the specified layer
    With PDImages.GetActiveImage.GetLayerByIndex(srcLayerIndex)
        .SetLayerOffsetX cParams.GetDouble("layer-offsetx")
        .SetLayerOffsetY cParams.GetDouble("layer-offsety")
    End With
    
    'Notify the parent of the change
    PDImages.GetActiveImage.NotifyImageChanged UNDO_LayerHeader, srcLayerIndex
    
    'Redraw the viewport
    ViewportEngine.Stage2_CompositeAllLayers PDImages.GetActiveImage(), FormMain.MainCanvas(0)

End Sub

'Given a layer, populate a rect with its coordinates (relative to the main image coordinates, always)
Public Sub FillRectForLayer(ByRef srcLayer As pdLayer, ByRef dstRect As RECT, Optional ByVal useCanvasModifiers As Boolean = False)
    
    With srcLayer
        dstRect.Left = .GetLayerOffsetX
        dstRect.Right = .GetLayerOffsetX + .GetLayerWidth(useCanvasModifiers)
        dstRect.Top = .GetLayerOffsetY
        dstRect.Bottom = .GetLayerOffsetY + .GetLayerHeight(useCanvasModifiers)
    End With
    
End Sub

'Given a layer, populate a rect with its coordinates (relative to the main image coordinates, always).
' As of PD 7.0, an additional "includeAffineTransforms" parameter is available.  This will return the bounds of the layer, after any/all
' affine transforms (rotate, etc) have been processed.
Public Sub FillRectForLayerF(ByRef srcLayer As pdLayer, ByRef dstRect As RectF, Optional ByVal useCanvasModifiers As Boolean = False, Optional ByVal includeAffineTransforms As Boolean = True)

    With srcLayer
        
        If includeAffineTransforms Then
            .GetLayerBoundaryRect dstRect
        Else
            dstRect.Left = .GetLayerOffsetX
            dstRect.Width = .GetLayerWidth(useCanvasModifiers)
            dstRect.Top = .GetLayerOffsetY
            dstRect.Height = .GetLayerHeight(useCanvasModifiers)
        End If
        
    End With

End Sub

'Given a layer index and an x/y position (ALREADY CONVERTED TO LAYER COORDINATE SPACE!), return an RGBQUAD for the pixel
' at that location.  Note that the returned result is unprocessed; e.g. it will be in premultipled format.
'
'If the pixel lies outside the layer boundaries, the function will return FALSE.  Make sure to check this before evaluating
' the RGBQUAD.
Public Function GetRGBAPixelFromLayer(ByVal layerIndex As Long, ByVal layerX As Long, ByVal layerY As Long, ByRef dstQuad As RGBQuad) As Boolean

    'Before doing anything else, check to see if the x/y coordinate even lies inside the image
    Dim tmpLayerRef As pdLayer
    Set tmpLayerRef = PDImages.GetActiveImage.GetLayerByIndex(layerIndex)
        
    If (layerX >= 0) And (layerY >= 0) And (layerX < tmpLayerRef.layerDIB.GetDIBWidth) And (layerY < tmpLayerRef.layerDIB.GetDIBHeight) Then
    
        'The point lies inside the layer, which means we need to figure out the color at this position
        GetRGBAPixelFromLayer = True
        
        'X and Y now represent the passed coordinate, but translated into the specified layer's coordinate space.
        ' Retrieve the color (and alpha, if relevant) at that point.
        Dim tmpData() As Byte
        Dim tSA As SafeArray2D
        PrepSafeArray tSA, tmpLayerRef.layerDIB
        CopyMemory ByVal VarPtrArray(tmpData()), VarPtr(tSA), 4
        
        Dim quickX As Long
        quickX = layerX * (tmpLayerRef.layerDIB.GetDIBColorDepth \ 8)
        
        'Failsafe bounds check
        If ((quickX + 3) < tmpLayerRef.layerDIB.GetDIBStride) And (layerY < tmpLayerRef.layerDIB.GetDIBHeight) Then
        
            With dstQuad
                .Blue = tmpData(quickX, layerY)
                .Green = tmpData(quickX + 1, layerY)
                .Red = tmpData(quickX + 2, layerY)
                If (tmpLayerRef.layerDIB.GetDIBColorDepth = 32) Then .Alpha = tmpData(quickX + 3, layerY)
            End With
            
        End If
        
        CopyMemory ByVal VarPtrArray(tmpData), 0&, 4
    
    'This coordinate does not lie inside the layer.
    Else
        GetRGBAPixelFromLayer = False
    End If

End Function

'Given an x/y pair (in IMAGE COORDINATES), return the top-most layer under that position, if any.
' The long-named optional parameter, "givePreferenceToCurrentLayer", will check the currently active layer before checking any others.
' If the mouse is over one of the current layer's points-of-interest (e.g. a resize node), the function will return that layer instead
' of others that lay atop it.  This allows the user to move and resize the current layer preferentially, and only if the current layer
' is completely out of the picture will other layers become activated.
Public Function GetLayerUnderMouse(ByVal imgX As Single, ByVal imgY As Single, Optional ByVal givePreferenceToCurrentLayer As Boolean = True) As Long

    Dim tmpRGBA As RGBQuad
    Dim curPOI As PD_PointOfInterest
    
    'Note that the caller passes us an (x, y) coordinate pair in the IMAGE coordinate space.  We will be using these coordinates to
    ' generate various new coordinate pairs in individual LAYER coordinate spaces  (This became necessary in PD 7.0, as layers
    ' may have non-destructive affine transforms active, which means we can't blindly switch between image and layer coordinate spaces!)
    Dim layerX As Single, layerY As Single
    
    'If givePreferenceToCurrentLayer is selected, check the current layer first.  If the mouse is over one of the layer's POIs, return
    ' the active layer without even checking other layers.
    If givePreferenceToCurrentLayer Then
    
        'Convert the passed image (x, y) coordinates into the active layer's coordinate space
        Drawing.ConvertImageCoordsToLayerCoords_Full PDImages.GetActiveImage(), PDImages.GetActiveImage.GetActiveLayer, imgX, imgY, layerX, layerY
    
        'See if the mouse is over a POI for the current layer (which may extend outside a layer's boundaries, because the clickable
        ' nodes have a radius greater than 0).  If the mouse is over a POI, return the active layer index immediately.
        curPOI = PDImages.GetActiveImage.GetActiveLayer.CheckForPointOfInterest(imgX, imgY)
        
        'If the mouse is over a point of interest, return this layer and immediately exit
        If (curPOI <> poi_Undefined) And (curPOI <> poi_Interior) Then
            GetLayerUnderMouse = PDImages.GetActiveImage.GetActiveLayerIndex
            Exit Function
        End If
        
    End If

    'With the active layer out of the way, iterate through all image layers in reverse (e.g. top-to-bottom).  If one is located
    ' beneath the mouse, and the hovered image section is non-transparent (pending the user's preference for this), return it.
    Dim i As Long
    For i = PDImages.GetActiveImage.GetNumOfLayers - 1 To 0 Step -1
    
        'Only evaluate the current layer if it is visible
        If PDImages.GetActiveImage.GetLayerByIndex(i).GetLayerVisibility Then
        
            'Convert the image (x, y) coordinate into the layer's coordinate space
            Drawing.ConvertImageCoordsToLayerCoords_Full PDImages.GetActiveImage(), PDImages.GetActiveImage.GetLayerByIndex(i), imgX, imgY, layerX, layerY
            
            'Only evaluate the current layer if the mouse is over it
            If Layers.GetRGBAPixelFromLayer(i, layerX, layerY, tmpRGBA) Then
            
                'A layer was identified beneath the mouse!  If the pixel is non-transparent, return this layer as the selected one.
                If (Not toolpanel_MoveSize.chkIgnoreTransparent.Value) Then
                    GetLayerUnderMouse = i
                    Exit Function
                Else
                
                    If (tmpRGBA.Alpha > 0) Then
                        GetLayerUnderMouse = i
                        Exit Function
                    End If
                
                End If
                            
            End If
        
        End If
    
    Next i
    
    'If we made it all the way here, there is no layer under this position.  Return -1 to signify failure.
    GetLayerUnderMouse = -1

End Function

'Crop a given layer to the current selection.
Public Sub CropLayerToSelection(ByVal layerIndex As Long)
    
    'First, make sure there is an active selection
    If (Not PDImages.GetActiveImage.IsSelectionActive) Then
        Message "No active selection found.  Crop abandoned."
        Exit Sub
    End If
    
    Message "Cropping layer to selected area..."
    
    'Because PD is awesome, we already have a function capable of doing this!
    If PDImages.IsImageActive() Then PDImages.GetActiveImage.EraseProcessedSelection layerIndex
    
    'Update the viewport
    ViewportEngine.Stage1_InitializeBuffer PDImages.GetActiveImage(), FormMain.MainCanvas(0)
    
End Sub

'If a function must rasterize a vector or text layer, it needs to call this function first.  This function will display a dialog
' asking the user for permission to rasterize the layer(s) in question.  Note that CANCEL is a valid return, so any callers need
' to handle that case gracefully!
Public Function AskIfOkayToRasterizeLayer(Optional ByVal srcLayerType As PD_LayerType = PDL_TEXT, Optional ByVal questionID As String = "RasterizeLayer", Optional ByVal multipleLayersInvolved As Boolean = False) As VbMsgBoxResult
    
    Dim questionText As String, yesText As String, noText As String, cancelText As String, rememberText As String, dialogTitle As String
    
    'If multiple layers are involved, we don't care about the current layer type
    If multipleLayersInvolved Then
    
        questionText = g_Language.TranslateMessage("This action will convert text and vector layers to image (raster) layers, meaning you can no longer modify layer-specific settings like text, font, color or shape.")
        questionText = questionText & vbCrLf & vbCrLf & g_Language.TranslateMessage("Are you sure you want to continue?")
        yesText = g_Language.TranslateMessage("Yes.  Convert text and vector layers to image (raster) layers.")
        noText = g_Language.TranslateMessage("No.  Leave text and vector layers as they are.")
    
    'If a single layer is involved, we'll further customize the prompt on a per-layer-type basis
    Else
    
        'Generate customized question text based on layer type
        Select Case srcLayerType
    
            Case PDL_TEXT, PDL_TYPOGRAPHY
                questionText = g_Language.TranslateMessage("This text layer will be changed to an image (raster) layer, meaning you can no longer modify its text or font settings.")
                questionText = questionText & vbCrLf & vbCrLf & g_Language.TranslateMessage("Are you sure you want to continue?")
                yesText = g_Language.TranslateMessage("Yes.  Please convert this text layer.")
                noText = g_Language.TranslateMessage("No.  Leave this text layer as it is.")
            
            Case Else
                Debug.Print "WARNING!  Unknown or invalid layer type passed to askIfOkayToRasterizeLayer!"
    
        End Select
    
    End If
    
    'Cancel text, "remember in the future" check box text, and dialog title are universal
    cancelText = g_Language.TranslateMessage("I can't decide.  Cancel this action.")
    rememberText = g_Language.TranslateMessage("In the future, automatically rasterize without prompting me")
    dialogTitle = "Rasterization required"
    
    'Display the dialog and return the result
    AskIfOkayToRasterizeLayer = Dialogs.PromptGenericYesNoDialog_SingleOutcome(questionID, questionText, yesText, noText, cancelText, rememberText, dialogTitle, vbYes, IDI_EXCLAMATION, vbYes)

End Function

'Rasterize a given layer.  Pass -1 to rasterize all vector layers.
Public Sub RasterizeLayer(Optional ByVal srcLayerIndex As Long = -1)

    '-1 tells us to rasterize all vector layers
    If (srcLayerIndex = -1) Then
    
        Dim i As Long
        For i = 0 To PDImages.GetActiveImage.GetNumOfLayers - 1
            If PDImages.GetActiveImage.GetLayerByIndex(i).IsLayerVector Then
            
                'Rasterize this layer, and notify the parent image of the change
                PDImages.GetActiveImage.GetLayerByIndex(i).RasterizeVectorData
                PDImages.GetActiveImage.NotifyImageChanged UNDO_Layer, i
            
            End If
        Next i
    
    Else
        
        'Rasterize just this one layer, and notify the parent image of the change
        If PDImages.GetActiveImage.GetLayerByIndex(srcLayerIndex).IsLayerVector() Then
            PDImages.GetActiveImage.GetLayerByIndex(srcLayerIndex).RasterizeVectorData
            PDImages.GetActiveImage.NotifyImageChanged UNDO_Layer, srcLayerIndex
        End If
        
    End If
    
    'Re-sync the interface
    SyncInterfaceToCurrentImage
    
    'Redraw the viewport
    ViewportEngine.Stage2_CompositeAllLayers PDImages.GetActiveImage(), FormMain.MainCanvas(0)

End Sub

'When a non-layered image is first loaded, the image itself is created as the base layer.  Unlike other software
' (which just assigns a stupid "Background" label), PD tries to generate a meaningful name for this layer.
' IMPORTANT NOTE: if passing a page index, note that the value is 0-BASED, so page "1" should be passed as "0".
'  (We do this to simplify interactions with the FreeImage plugin, which handles the bulk of our multipage interface.)
Public Function GenerateInitialLayerName(ByRef srcFile As String, Optional ByVal suggestedFilename As String = vbNullString, Optional ByVal imageHasMultiplePages As Boolean = False, Optional ByRef srcImage As pdImage, Optional ByRef srcDIB As pdDIB, Optional ByVal currentPageIndex As Long = 0) As String
    
    'If a multipage image is loaded as individual layers, each layer will receive a custom name to reflect its position in the
    ' original file.  (For example, when loading .ICO files with multiple icons inside, PD will automatically add the name and
    ' original bit-depth to each layer, as relevant.)
    If imageHasMultiplePages Or (srcImage.GetOriginalFileFormat = FIF_ICO) Then
        
        Select Case srcImage.GetOriginalFileFormat
        
            'GIFs are called "frames" instead of pages
            Case PDIF_GIF
                GenerateInitialLayerName = g_Language.TranslateMessage("Frame %1", CStr(currentPageIndex))
                
            'Icons have their actual dimensions added to the layer name
            Case FIF_ICO
                If srcDIB.GetOriginalFreeImageColorDepth = 0 Then
                    GenerateInitialLayerName = g_Language.TranslateMessage("Icon (%1x%2)", CStr(srcDIB.GetDIBWidth), CStr(srcDIB.GetDIBHeight))
                Else
                    GenerateInitialLayerName = g_Language.TranslateMessage("Icon (%1x%2, %3 bpp)", CStr(srcDIB.GetDIBWidth), CStr(srcDIB.GetDIBHeight), CStr(srcDIB.GetOriginalFreeImageColorDepth))
                End If
                
            'Any other format is treated as "pages" (0-based index)
            Case Else
                GenerateInitialLayerName = g_Language.TranslateMessage("Page %1", CStr(currentPageIndex + 1))
                
        End Select
    
    'The first layer of single-layer images use a simpler naming system
    Else
        If (LenB(suggestedFilename) = 0) Then
            GenerateInitialLayerName = Files.FileGetName(srcFile, True)
        Else
            GenerateInitialLayerName = suggestedFilename
        End If
    End If
    
End Function
