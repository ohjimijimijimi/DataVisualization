//
//  ViewModel.swift
//  DataVisualization
//
//  Created by Roberto Previdi on 28/12/15.
//  Copyright © 2015 CocoaPods. All rights reserved.
//

import Foundation
import RxSwift
import RxCocoa

class ViewModel {
	var cellNib:UINib! = nil
	func cellFactory(index:Int,item:Any,cell:UITableViewCell)->Void {}
}

class ConcreteViewModel<Data,Cell>:ViewModel
{
	var cellFactoryClosure:(index:Int,item:Data,cell:Cell)->Void
	init(cellName:String,cellFactory:(index:Int,item:Data,cell:Cell)->Void) {
		self.cellFactoryClosure=cellFactory
		super.init()
		cellNib=UINib(nibName: cellName, bundle: nil)
	}
	override func cellFactory(index: Int, item: Any, cell: UITableViewCell) {
		guard let item=item as? Data,
			cell=cell as? Cell
			else {fatalError("ViewModel used with wrong data type or cell")}
		self.cellFactoryClosure(index: index, item: item, cell: cell)
	}
}

protocol Visualizable {
	static func defaultViewModel()->ViewModel
	static func api()->Observable<[Self]>
}