local H = require("spec.helpers.engine")

describe("Difficulty and XP", function()
  local ns, D, XP
  before_each(function()
    ns = H.load()
    D, XP = ns.Difficulty, ns.XP
  end)

  it("grey level fallback", function()
    assert.equals(0, D.greyAtOrBelow(5)); assert.equals(12, D.greyAtOrBelow(18))
    assert.equals(31, D.greyAtOrBelow(40)); assert.equals(47, D.greyAtOrBelow(60))
  end)

  it("colors", function()
    assert.equals("red", D.color(23, 18, 12)); assert.equals("orange", D.color(21, 18, 12))
    assert.equals("yellow", D.color(16, 18, 12)); assert.equals("green", D.color(13, 18, 12))
    assert.equals("grey", D.color(12, 18, 12))
  end)

  it("xp scaling", function()
    local q = { id = 4763, xp = 1700, level = 18 }
    assert.equals(1700, XP.estimate(q, 18)); assert.equals(1700, XP.estimate(q, 23))
    assert.equals(1360, XP.estimate(q, 24)); assert.equals(340, XP.estimate(q, 27))
    assert.equals(170, XP.estimate(q, 30)); assert.equals(0, XP.estimate({ id = 1, level = 10 }, 10))
    assert.equals(1875, XP.estimate(q, 18, { [4763] = { [18] = 1875 } }))
  end)

  it("color is grey when a level is missing", function()
    assert.equals("grey", D.color(nil, 18, 12))
    assert.equals("grey", D.color(18, nil, 12))
    assert.equals("grey", D.color(nil, nil))
  end)

  it("color defaults greyAtOrBelow from the player level when nil", function()
    -- playerLevel 18 -> greyAtOrBelow 12, so quest level 13 is green, 12 is grey
    assert.equals("green", D.color(13, 18, nil))
    assert.equals("grey", D.color(12, 18, nil))
  end)

  it("xp factor boundaries at d = 5 and d = 10", function()
    assert.equals(1.0, XP.factor(20, 15)) -- d = 5
    assert.equals(0.1, XP.factor(20, 10)) -- d = 10
    assert.equals(0.1, XP.factor(20, 1))  -- d > 10 stays at 0.1
  end)
end)
