//
//  SectionedTableView.swift
//  DataVisualization
//
//  Created by Roberto Previdi on 28/12/15.
//  Copyright © 2015 CocoaPods. All rights reserved.
//

import Foundation
import RxSwift
import RxCocoa

public protocol Sectioner
{
	init(viewForActivityIndicator:UIView?)
	typealias Data
	typealias Section
	var sections:Observable<[(Section,[Data])]> {get}
	mutating func resubscribe()
}

public protocol AutoSectionedTableView:Disposer {
	typealias Data:Visualizable
	typealias Section:SectionVisualizable
	typealias SectionerType:Sectioner
	var dataViewModel:ViewModel {get}
	var sectionViewModel:ViewModel {get}
	
	func setupTableView(tableView:UITableView,vc:UIViewController)
	var sectioner:SectionerType! {get}
}
class EnrichedTapGestureRecognizer<T>:UITapGestureRecognizer
{
	var obj:T
	init(target: AnyObject?, action: Selector,obj:T) {
		self.obj=obj
		super.init(target: target, action: action)
	}
}
public enum OnSelectSectionedBehaviour<T>
{
	case Detail(segue:String)
	case SectionDetail(segue:String) // shows the detail of the section, even if starting from a data cell
	case Action(action:(d:T)->())
}
public class AutoSectionedTableViewManager<
	DataType:Visualizable,
	SectionType:SectionVisualizable,
	_SectionerType:Sectioner where _SectionerType.Data==DataType,_SectionerType.Section==SectionType
	>:NSObject,AutoSectionedTableView,UITableViewDelegate,ControllerWithTableView
{
	public let disposeBag=DisposeBag()
	public var dataBindDisposeBag=DisposeBag()
	public typealias Data=DataType
	public typealias Section=SectionType
	public typealias SectionerType=_SectionerType
	
	typealias RxSectionModel=SectionModel<Section,Data>
	let dataSource=RxTableViewSectionedReloadDataSource<RxSectionModel>()
	var sections=Variable([RxSectionModel]())
	
	var onDataClick:((row:Data)->())?=nil
	var clickedDataObj:Data?

	var onSectionClick:((section:Section)->())?=nil
	var clickedSectionObj:Section?

	public var dataViewModel=Data.defaultViewModel()
	public var sectionViewModel=Section.defaultSectionViewModel()
	public var sectioner:SectionerType!
	var vc:UIViewController!
	var tableView:UITableView!

	
	
	public override init() {super.init()}
	public func setupTableView(tableView:UITableView,vc:UIViewController)
	{
		guard let dataNib=dataViewModel.cellNib,
			sectionNib=sectionViewModel.cellNib
		else {fatalError("No cellNib defined: are you using ConcreteViewModel properly?")}
		
		self.vc=vc
		self.tableView=tableView

		sectioner=SectionerType(viewForActivityIndicator: self.tableView)
		
		switch dataNib
		{
		case .First(let nib):
			tableView.registerNib(nib, forCellReuseIdentifier: "cell")
		case .Second(let clazz):
			tableView.registerClass(clazz, forCellReuseIdentifier: "cell")
		}
			
		switch sectionNib
		{
		case .First(let nib):
			tableView.registerNib(nib, forHeaderFooterViewReuseIdentifier: "section")
		case .Second(let clazz):
			tableView.registerClass(clazz, forHeaderFooterViewReuseIdentifier: "section")
		}
		tableView.delegate=self
		
		dataSource.cellFactory={
			(tableView,indexPath,item:Data) in
			guard let cell=tableView.dequeueReusableCellWithIdentifier("cell")
				else {fatalError("why no cell?")}
			self.dataViewModel.cellFactory(indexPath.row, item: item, cell: cell)
			self.cellDecorators.forEach({ dec in
				dec(cell: cell)
			})
			return cell
		}
		
		bindData()
		
		if let Cacheable=SectionerType.self as? Cached.Type
		{
			setupRefreshControl{
				Cacheable.invalidateCache()
				self.sectioner.resubscribe()
				self.dataBindDisposeBag=DisposeBag()
				self.bindData()
			}
		}
		
	}
	func bindData()
	{
		sectioner.sections.subscribeNext { (secs:[(Section, [Data])]) -> Void in
			self.sections.value=secs.map{ (s,d) in
				RxSectionModel(model: s, items: d)
			}
		}.addDisposableTo(dataBindDisposeBag)
		
		sections.asObservable().bindTo(tableView.rx_itemsWithDataSource(dataSource))
			.addDisposableTo(dataBindDisposeBag)
		
		sections.asObservable()
			.map { array in
				array.isEmpty
			}
			.subscribeNext { empty in
				if empty {
					self.tableView.backgroundView=self.sectionViewModel.viewForEmptyList
				}
				else
				{
					self.tableView.backgroundView=nil
				}
			}.addDisposableTo(dataBindDisposeBag)

		
	}
	public func tableView(tableView: UITableView,
		viewForHeaderInSection section: Int) -> UIView?
	{
		guard let hv=tableView.dequeueReusableHeaderFooterViewWithIdentifier("section")
			else {fatalError("why no section cell?")}
		let s=sections.value[section].model
		sectionViewModel.cellFactory(section, item: s, cell: hv)
		if onSectionClick != nil
		{
			let gestRec=EnrichedTapGestureRecognizer(target: self, action: "sectionTitleTapped:",obj:s)
			hv.addGestureRecognizer(gestRec)
		}

		return hv
	}
	func sectionTitleTapped(gr:UITapGestureRecognizer)
	{
		guard let gr=gr as? EnrichedTapGestureRecognizer<Section> else {return}
		clickedSectionObj=gr.obj
		onSectionClick?(section:gr.obj)
	}
	public var cellDecorators:[CellDecorator]=[]
	public func tableView(tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
		guard let hv=tableView.dequeueReusableHeaderFooterViewWithIdentifier("section")
			else {fatalError("why no section cell?")}
		return hv.bounds.height
	}
	public func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
		dump(indexPath)
		let item=dataSource.itemAtIndexPath(indexPath)
		clickedDataObj=item
		clickedSectionObj=sections.value[indexPath.section].model
		onDataClick?(row:item)
	}
	
	var dataDetailSegue:String?=nil
	var dataDetailSectionSegue:String?=nil
	public func setupDataOnSelect(onSelect:OnSelectSectionedBehaviour<Data>)
	{
		switch onSelect
		{
		case .Detail(let segue):
			dataDetailSegue=segue
			onDataClick = { row in
				self.vc.performSegueWithIdentifier(segue, sender: nil)
			}
		case .SectionDetail(let segue):
			dataDetailSectionSegue=segue
			onDataClick = { row in
				self.vc.performSegueWithIdentifier(segue, sender: nil)
			}
			
		case .Action(let closure):
			self.onDataClick=closure
		}
		
		switch onSelect
		{
		case .Detail(_):
			fallthrough
		case .SectionDetail(_):
			
			let dec:CellDecorator={ (cell:UITableViewCell) in
				cell.accessoryType=UITableViewCellAccessoryType.DisclosureIndicator
			}
			cellDecorators.append(dec)
			listenForSegue()
		default:
			_=0
		}
	}
	var sectionDetailSegue:String?=nil
	public func setupSectionOnSelect(onSelect:OnSelectBehaviour<Section>)
	{
		switch onSelect
		{
		case .Detail(let segue):
			sectionDetailSegue=segue
			onSectionClick = { row in
				self.vc.performSegueWithIdentifier(segue, sender: nil)
			}
			listenForSegue()
		case .Action(let closure):
			self.onSectionClick=closure
		}
	}
	var listeningForSegue=false
	public func listenForSegue() {
		guard !listeningForSegue else {return}
		listeningForSegue=true
		vc.rx_prepareForSegue.subscribeNext { (segue,_) in
			guard var dest=segue.destinationViewController as? DetailView,
				let identifier=segue.identifier else {return}
			switch identifier
			{
			case let val where val==self.dataDetailSegue:
				dest.detailManager.object=self.clickedDataObj
			case let val where val==self.dataDetailSectionSegue:
				dest.detailManager.object=self.clickedSectionObj
			case let val where val==self.sectionDetailSegue:
				dest.detailManager.object=self.clickedSectionObj
			default:
				_=0
			}
			}.addDisposableTo(disposeBag)
	}
}

public class AutoSearchableSectionedTableViewManager<
DataType:Visualizable,
SectionType:SectionVisualizable,
_SectionerType:Sectioner where _SectionerType.Data==DataType,_SectionerType.Section==SectionType
>:AutoSectionedTableViewManager<DataType,SectionType,_SectionerType>,Searchable
{
	public var searchController:UISearchController!
	public override func setupTableView(tableView:UITableView,vc:UIViewController)
	{
		self.vc=vc
		self.tableView=tableView
		setupSearchController()
		super.setupTableView(tableView, vc:vc)
	}
	public typealias DataFilteringClosure=(d:DataType,s:String)->Bool
	public typealias SectionFilteringClosure=(d:SectionType,s:String)->Bool
	
	public var dataFilteringClosure:DataFilteringClosure
	public var sectionFilteringClosure:SectionFilteringClosure
	public init(dataFilteringClosure:DataFilteringClosure,sectionFilteringClosure:SectionFilteringClosure) {
		self.dataFilteringClosure=dataFilteringClosure
		self.sectionFilteringClosure=sectionFilteringClosure
		super.init()
	}
	override func bindData() {
		let search=searchController.searchBar.rx_text.asObservable()
		typealias SectionAndData=(Section,[Data])
		let dataOrSearch=Observable.combineLatest(sectioner.sections, search, resultSelector: { (d:[SectionAndData], s:String) -> [SectionAndData] in
			switch s
			{
			case "": return d
			default:
				var res=[SectionAndData]()
				for (sec,data) in d
				{
					if self.sectionFilteringClosure(d: sec, s: s)
					{
						res.append((sec,data))
						continue
					}
					
					var matchingData=[Data]()
					for item in data
					{
						if self.dataFilteringClosure(d: item, s: s)
						{
							matchingData.append(item)
						}
					}
					if !matchingData.isEmpty
					{
						res.append((sec,matchingData))
					}
				}
				return res
			}
		}).shareReplayLatestWhileConnected()
		
		dataOrSearch
			.subscribeNext { (secs:[(Section, [Data])]) -> Void in
			self.sections.value=secs.map{ (s,d) in
				RxSectionModel(model: s, items: d)
			}
			}.addDisposableTo(dataBindDisposeBag)
		
		
		sections.asObservable().bindTo(tableView.rx_itemsWithDataSource(dataSource))
			.addDisposableTo(dataBindDisposeBag)
		
		dataOrSearch
			.map { array in
				array.isEmpty
			}
			.subscribeNext { empty in
				
				switch (empty,self.searchController.searchBar.text)
				{
				case (true,let s) where s==nil || s=="":
					self.tableView.backgroundView=self.sectionViewModel.viewForEmptyList
				case (true,_):
					self.tableView.backgroundView=self.sectionViewModel.viewForEmptySearch
				default:
					self.tableView.backgroundView=nil
				}
			}.addDisposableTo(dataBindDisposeBag)

		
	}
}