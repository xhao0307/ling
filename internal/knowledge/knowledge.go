package knowledge

import "ling/internal/model"

var BaseKnowledge = []model.KnowledgeItem{
	{
		ObjectType: "manhole",
		Aliases:    []string{"well_cover", "drain_cover"},
		Facts: []string{
			"井盖是地下设施检修和维护的重要入口。",
			"很多城市会在井盖图案中加入本地文化元素。",
		},
		Quiz: []model.QuizItem{
			{Question: "井盖的一个重要作用是什么？", Answer: "检修"},
			{Question: "井盖通常在地下管线的上方还是下方？", Answer: "上方"},
		},
	},
	{
		ObjectType: "mailbox",
		Aliases:    []string{"post_box"},
		Facts: []string{
			"邮箱是信件和明信片的集中投递点。",
			"邮政系统会通过邮编快速分拣信件。",
		},
		Quiz: []model.QuizItem{
			{Question: "人们通常会把什么投进邮箱？", Answer: "信件"},
			{Question: "帮助信件快速送达的编码是什么？", Answer: "邮编"},
		},
	},
	{
		ObjectType: "tree",
		Aliases:    []string{"street_tree"},
		Facts: []string{
			"树木会吸收二氧化碳并释放氧气。",
			"行道树通过遮阴可以降低城市体感温度。",
		},
		Quiz: []model.QuizItem{
			{Question: "树木有助于吸收哪种气体？", Answer: "二氧化碳"},
			{Question: "树木会释放我们需要呼吸的什么气体？", Answer: "氧气"},
		},
	},
	{
		ObjectType: "road_sign",
		Aliases:    []string{"traffic_sign", "sign"},
		Facts: []string{
			"路牌会传达警示、规则和方向信息。",
			"路牌的形状和颜色能帮助人们快速识别含义。",
		},
		Quiz: []model.QuizItem{
			{Question: "路牌主要传达哪类信息？", Answer: "规则"},
			{Question: "除了文字，什么特征能帮助快速识别路牌？", Answer: "形状"},
		},
	},
	{
		ObjectType: "traffic_light",
		Aliases:    []string{"signal_light"},
		Facts: []string{
			"红绿灯用于协调车辆和行人的通行秩序。",
			"在常见交通规则中，红灯停、绿灯行。",
		},
		Quiz: []model.QuizItem{
			{Question: "交通信号灯中红灯通常表示什么？", Answer: "停止"},
			{Question: "交通信号灯中绿灯通常表示什么？", Answer: "通行"},
		},
	},
}
